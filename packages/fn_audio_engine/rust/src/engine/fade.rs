//! 淡入淡出与等功率交叉淡化（消除数字信号的"啪嗒"声）。
//!
//! # 要解决的问题
//!
//! 直接把一帧从满幅切到 0（或反过来），是一次**单位阶跃**：频谱展到全频段，
//! 听感就是一声"啪嗒"。三个地方会出这个问题：
//!
//! 1. 曲目开头第一个样��不是 0（录音起始就是正弦相位）；
//! 2. 曲目最后一个样本非 0 就直接结束；
//! 3. 暂停/停止时增益一步归零。
//!
//! 所以这三种场合都要**斜坡**（ramp）而不是阶跃。
//!
//! # 斜坡多长
//!
//! 两档完全不同的用途，别混为一谈：
//!
//! * **消爆音**（暂停/停止的软静音）：20 ms @ 44.1 kHz 是 882 帧，每帧增益步进
//!   ≤ 1.13e-3，残余阶跃在 −59 dBFS，比阶跃小 58 dB；同时 20 ms 远低于"听起来
//!   变软"的阈值（约 100 ms）。
//! * **曲目淡入淡出**（听感上的淡）：默认 800 ms 进 / 1500 ms 出。这两个数字
//!   取代了早先的 20/40 ms——那只是消爆音的量级，用户反馈"淡入淡出没有效果"
//!   是对的，20 ms 根本听不见。淡出比淡入长，因为耳朵对"突然消失"更敏感。
//!
//! # 什么时候**不**做
//!
//! 交叉淡化用等功率（sin/cos）而不是线性：两条不相关的信号线性相加会
//! 在中点掉 3 dB（功率相加才是恒定），听感上像是中间塌了一下。

use crate::engine::pcm::Planar;

/// 默认淡入时长（毫秒）：听得出是淡入，又不至于把开头吃掉太多。
pub const DEFAULT_FADE_IN_MS: u32 = 800;
/// 默认淡出时长（毫秒）：比淡入长，耳朵对"突然消失"更敏感。
pub const DEFAULT_FADE_OUT_MS: u32 = 1500;
/// 用户可调上限：8 秒。再长就不像淡出了，暂停会变"软"。
pub const MAX_FADE_MS: u32 = 8_000;

/// 时长（毫秒）→ 帧数。**0 毫秒返回 0 帧**（真正的"关闭"，位精确直通）。
///
/// 旧实现把 0 归一成 1 帧，害得"关闭淡入"其实仍然动了一个样本。
pub fn ms_to_frames(sample_rate: u32, ms: u32) -> usize {
    let ms = ms.min(MAX_FADE_MS);
    if ms == 0 {
        return 0;
    }
    ((sample_rate as u64 * ms as u64) / 1000) as usize
}

/// 淡入：把开头 `frames` 帧从 0 线性升到 1。
///
/// 曲线取 `g(i) = i/n`：**首帧精确为 0**（起点不接缝，不会有"啪"），
/// 末帧为 `(n-1)/n`，与斜坡内部每一级的步进 `1/n` 同量级，听不出接缝。
///
/// 淡入长度超过总帧数时按总帧数走——否则整首都得乘一个 <1 的系数，等于降音量。
pub fn fade_in(planar: &mut Planar, frames: usize) {
    let total = crate::engine::pcm::frames(planar);
    if total == 0 || frames == 0 {
        return;
    }
    let n = frames.min(total);
    for ch in planar.iter_mut() {
        for (i, s) in ch.iter_mut().take(n).enumerate() {
            *s *= i as f64 / n as f64;
        }
    }
}

/// 淡出：把结尾 `frames` 帧线性降到 0。
///
/// 曲线取 `g(i) = (n-1-i)/(n-1)`：**末帧精确为 0**（接静音没有阶跃），
/// 这是淡出比淡入更重要的方向——停止播放时那个"啪"就是最后这一跳造成的。
pub fn fade_out(planar: &mut Planar, frames: usize) {
    let total = crate::engine::pcm::frames(planar);
    if total == 0 || frames == 0 {
        return;
    }
    let n = frames.min(total);
    let start = total - n;
    let last = (n - 1).max(1) as f64;
    for ch in planar.iter_mut() {
        for (i, s) in ch[start..].iter_mut().enumerate() {
            *s *= (last - i as f64) / last;
        }
    }
}

/// 等功率（constant-power）交叉淡化：`out = old·cos(t) + new·sin(t)`。
///
/// `t = (i+1)/n`：淡化区最后一帧精确等于 `new`，切换点没有接缝。
/// `xfade_frames` 为淡化长度，其余帧直接取 `new`。等功率的意义：两条不相关
/// 信号的能量相加恒定，线性相加会在中点掉 3 dB，听起来像中间"塌"了一下。
///
/// 热切换走的是 [`crossfade_blend_in_place`]（不分配）；这个版本是它的对照实现。
#[cfg_attr(not(test), allow(dead_code))]
pub fn crossfade_blend(old: &Planar, new: &Planar, xfade_frames: usize, out: &mut Planar) {
    let channels = old.len().min(new.len()).min(out.len());
    for ch in 0..channels {
        let frames = old[ch].len().min(new[ch].len()).min(out[ch].len());
        let n = xfade_frames.min(frames);
        for i in 0..frames {
            out[ch][i] = if i < n && n > 0 {
                let angle = (i + 1) as f64 / n as f64 * std::f64::consts::FRAC_PI_2;
                old[ch][i] * angle.cos() + new[ch][i] * angle.sin()
            } else {
                new[ch][i]
            };
        }
    }
}

/// 等功率交叉淡化，就地写入 `old`（不额外分配）。
///
/// 与 [`crossfade_blend`] 逐样本等价，只是省掉一次拷贝——热切换每块都要用。
pub fn crossfade_blend_in_place(old: &mut Planar, new: &Planar, xfade_frames: usize) {
    let channels = old.len().min(new.len());
    for ch in 0..channels {
        let frames = old[ch].len().min(new[ch].len());
        let n = xfade_frames.min(frames);
        for i in 0..n {
            let angle = (i + 1) as f64 / n as f64 * std::f64::consts::FRAC_PI_2;
            old[ch][i] = old[ch][i] * angle.cos() + new[ch][i] * angle.sin();
        }
        for i in n..frames {
            old[ch][i] = new[ch][i];
        }
    }
}

/// 软静音斜坡：连续地把 `gain` 从 `from` 滑到 `to`（就地乘到 planar 上）。
///
/// 用于暂停/停止：先斜坡到 0，再真正停掉音源。用 20 ms 而不是一步归零，
/// 残余阶跃 −59 dBFS，听不见。
///
/// 当前 Web 播放链路的软静音在**客户端**做（浏览器音频图里斜坡更及时，
/// 服务端此刻已经在推下一块了），所以这里只作为被测过的原语留着。
#[cfg_attr(not(test), allow(dead_code))]
pub fn ramp_gain(planar: &mut Planar, from: f64, to: f64, frames: usize) {
    if (from - 1.0).abs() < 1e-12 && (to - 1.0).abs() < 1e-12 {
        return; // 单位增益：位精确直通，不做任何乘法。
    }
    let n = frames.max(1);
    for ch in planar.iter_mut() {
        let k = n.min(ch.len());
        for (i, s) in ch.iter_mut().take(k).enumerate() {
            let t = i as f64 / n as f64;
            *s *= from + (to - from) * t;
        }
        for s in ch.iter_mut().skip(k) {
            *s *= to;
        }
    }
}


