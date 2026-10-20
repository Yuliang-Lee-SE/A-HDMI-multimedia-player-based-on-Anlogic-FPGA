`timescale 1ns/1ps
module tb_osd_sdram_probe;
tb_zoom_real_sdram #(.H(48),.FORCED_REFRESH(1),.DISPLAY_COMMIT(1)) test();
integer n;
initial begin
 for(n=0;n<20;n=n+1) begin
  #100000;
  $display("PROBE t=%0t init=%b req=%b ack=%b ready=%b fifo_reset=%b hold=%b first=%b release=%b state=%0d count=%0d finished=%b",$time,test.init_done,test.req,test.ack,test.ready,test.store.write_fifo_reset,test.store.write_reset_mem_hold,test.store.write_reset_first,test.store.write_reset_release,test.store.frame_fifo_write_m0.state,test.count,test.finished_seen);
 end
end
endmodule
