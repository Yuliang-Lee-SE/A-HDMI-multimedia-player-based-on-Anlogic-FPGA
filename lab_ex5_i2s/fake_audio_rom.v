//======================================================================
// 行为级音频 ROM 模型（供 S6 使用，不需要器件库）
//   内容：doa = addra[7:0]，即地址每 +1、样本值 +1
//   这样"每 6 个 48kHz 帧取一次新样点"的零阶保持一眼能看出来：
//   同一个值会连续出现 6 帧，然后跳到下一个值。
//   真正的硬件 ROM 是 AUDIO_SPEECH_ROM（8bit × 49152，读延迟 1 拍），
//   这里的 always @(posedge clka) 与之一致。
//======================================================================
`timescale 1ns/1ps
module fake_audio_rom #(
  parameter integer DEPTH = 49152
)(
  input  wire [15:0] addra,
  input  wire        clka,
  output reg  [7:0]  doa
);
  always @(posedge clka) begin
    doa <= (addra >= DEPTH) ? 8'd0 : addra[7:0];
  end
endmodule
