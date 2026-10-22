`timescale 1ns/1ps
module tb_fat32_ro;
 parameter MAX_FILES=32, CHAIN_LIMIT=1024, DIR_LIMIT=4096;
 localparam SW=$clog2(MAX_FILES), CW=$clog2(MAX_FILES+1);
 reg clk=0; always #5 clk=~clk;
 reg rst=1, mount_valid=0, open_valid=0, data_ready=0;
 reg [31:0] media_sectors;
 reg [13:0] open_id;
 reg [SW-1:0] index_slot=0;
 wire mount_ready,mounted,mount_done,open_ready,index_valid,data_valid,file_done,error_valid;
 wire [CW-1:0] file_count;
 wire [13:0] index_id;
 wire [31:0] index_size;
 wire [7:0] data,error_code;
 wire req_valid,cancel_valid;
 wire [31:0] req_lba,req_tag,cancel_tag;
 reg req_ready=0,rsp_valid=0,rsp_done=0,rsp_error=0;
 reg [31:0] rsp_tag=0;
 reg [7:0] rsp_data=0;
 fat32_ro #(.MAX_FILES(MAX_FILES),.MAX_CHAIN(CHAIN_LIMIT),.MAX_DIR_ENTRIES(DIR_LIMIT),.IO_TIMEOUT(2048),.STALL_TIMEOUT(256)) dut(.*);
 string root;
 integer cfg,image_fd,golden_fd,nfiles,want_mount,want_file,inject,target_lba;
 integer assets[0:127],lengths[0:127];
 integer rc,i,j,k,cycles=0,checked=0,requests=0,stale=0,cancels=0;
 integer expected_eoc=-1, eoc_mask=0, fat_hits=0, fat_misses=0;
 integer tx_pos=0,tx_delay=0,tx_mode=0,tx_len=512;
 reg busy=0, fault_used=0, disable_fault=0, late_pending=0;
 reg [31:0] tx_tag;
 reg [7:0] block_data[0:512];
 reg held=0; reg [7:0] held_data;
 task die(input string msg);
  begin $display("FAIL %s cycle=%0d state=%0d error=%0d current=%0d pos=%0d entry_cluster=%0d clusters=%0d fat=%h lba=%0d",msg,cycles,dut.state,error_code,dut.current,dut.pos,dut.entry_cluster,dut.clusters,dut.fat_entry,req_lba); $fatal(1); end
 endtask
 always @(posedge clk) begin
  cycles<=cycles+1;
  if(cycles>5000000) die("global watchdog");
  if(rst) begin
   // Sector adapter reset is mandatory with core reset; it flushes old transactions.
   busy<=0; rsp_valid<=0; rsp_done<=0; rsp_error<=0; req_ready<=0; held<=0; late_pending<=0;
  end else begin
   if($isunknown(dut.state) || !$onehot(dut.state)) die("non-onehot control state");
   if((dut.state==dut.REQ || dut.state==dut.RECEIVE) && ($isunknown(dut.return_state) || !$onehot(dut.return_state))) die("non-onehot return state");
   if(dut.state==dut.FAT) begin
    if(dut.cache_valid && dut.cached_lba==dut.fat_lba) fat_hits<=fat_hits+1;
    else fat_misses<=fat_misses+1;
   end
   if(dut.state==dut.FAT_VALUE && dut.fat_entry>=28'hffffff8) eoc_mask<=eoc_mask | (1<<dut.fat_entry[2:0]);
   if(error_valid) $display("ERROR_DIAG code=%0d current=%0d next=%0d pos=%0d entry_cluster=%0d clusters=%0d fat=%h lba=%0d",error_code,dut.current,dut.next_cluster,dut.pos,dut.entry_cluster,dut.clusters,dut.fat_entry,req_lba);
   req_ready<=!busy && !(inject==10 && !disable_fault);
   rsp_valid<=0; rsp_done<=0; rsp_error<=0;
   if(cancel_valid) begin
    cancels<=cancels+1;
    if(busy && cancel_tag==tx_tag) begin busy<=0; late_pending<=1; end
   end
   if(req_valid && req_ready) begin
    if(busy) die("overlapping requests");
    if(req_lba>=media_sectors) die("request beyond media");
    requests<=requests+1; busy<=1; req_ready<=0;
    tx_tag<=req_tag; tx_pos<=0; tx_delay<=3+(requests%7); tx_mode<=0; tx_len<=512;
    if(late_pending) begin tx_mode<=5; late_pending<=0; end
    rc=$fseek(image_fd,req_lba*512,0);
    if(rc!=0) die("image seek");
    for(k=0;k<512;k=k+1) begin
     rc=$fgetc(image_fd); if(rc<0) die("image unexpectedly short");
     block_data[k]=rc;
    end
    block_data[512]=8'hbb;
    if(!fault_used && !disable_fault && ((req_lba==target_lba && ((inject>=1 && inject<=5) || inject>=11))||
           (req_lba==0 && inject==9))) begin
     fault_used<=1; tx_mode<=inject;
     if(inject==3) tx_len<=511;
     if(inject==4) tx_len<=513;
    end
   end else if(busy) begin
    rsp_tag<=tx_tag;
    if(tx_delay>0) tx_delay<=tx_delay-1;
    else if(tx_mode==1 || tx_mode==9 || tx_mode==15 || tx_mode==17 ||
             (tx_mode==11 && tx_pos==128) || (tx_mode==19 && tx_pos==511)) begin rsp_error<=1; busy<=0; end
    else if(tx_mode==2 || tx_mode==16 || (tx_mode==12 && tx_pos==128) || (tx_mode==13 && tx_pos==512)) begin end // wait for cancel
    else if(tx_mode==5) begin
     // Deliberately interleave stale bytes/done/error before a correct transaction.
     rsp_tag<=tx_tag-1; rsp_valid<=1; rsp_done<=1; rsp_error<=1;
     rsp_data<=8'hde; tx_mode<=0; tx_delay<=4; stale<=stale+1;
    end else if(tx_pos==tx_len) begin rsp_done<=1; busy<=0; end
    else begin
     rsp_valid<=1; rsp_data<=block_data[tx_pos]; tx_pos<=tx_pos+1;
     if(tx_mode==18 && tx_pos==511) begin rsp_done<=1; busy<=0; end
     if(tx_pos%11==0) tx_delay<=2;
    end
   end
   if(held && !rst && !error_valid && (!data_valid || data!==held_data)) die("valid/data changed under backpressure");
   held<=data_valid && !data_ready;
   held_data<=data;
   if(data_valid && file_done) die("completion concurrent with unaccepted byte");
  end
 end
 task pulse_reset;
  begin
   @(negedge clk); rst=1; mount_valid=0; open_valid=0; data_ready=0;
   repeat(4) @(negedge clk); rst=0;
  end
 endtask
 task mount;
  begin
   wait(mount_ready); @(negedge clk); mount_valid=1;
   @(negedge clk); mount_valid=0;
   wait(mount_done || error_valid);
  end
 endtask
 task start_file(input integer asset);
  begin
   wait(open_ready); @(negedge clk); open_id=asset; open_valid=1;
   @(negedge clk); open_valid=0;
  end
 endtask
 task read_file(input integer size, input integer expected_error);
  integer bytes_read, expected, ticks;
  begin
   bytes_read=0; ticks=0;
   // Sampling at posedge observes the exact valid/ready handshake.
   while(!file_done && !error_valid) begin
    @(negedge clk);
    if(file_done || error_valid) break;
    data_ready=(ticks%13!=0 && ticks%13!=1 && ticks%13!=2);
    if(inject==6 && !disable_fault) data_ready=0;
    @(posedge clk);
    if(data_valid && data_ready) begin
     if(bytes_read>=size) die("extra file bytes");
     rc=$fscanf(golden_fd,"%h",expected);
     if(rc!=1 || data!==expected[7:0]) begin
      $display("offset=%0d got=%02h expected=%02h",bytes_read,data,expected[7:0]); die("byte mismatch");
     end
     bytes_read=bytes_read+1; checked=checked+1;
    end
    #1; ticks=ticks+1;
   end
   if(expected_error!=0) begin
    if(!error_valid || error_code!=expected_error || file_done) die("wrong file error");
    $display("EXPECTED_FILE_ERROR code=%0d bytes=%0d",error_code,bytes_read);
   end else if(!file_done || error_valid || bytes_read!=size) begin
    $display("bytes=%0d size=%0d",bytes_read,size); die("file completion/length");
   end
   @(negedge clk); data_ready=0;
  end
 endtask
 initial begin
  if(!$value$plusargs("CASE=%s",root)) die("missing CASE argument");
  rc=$value$plusargs("EOC=%d",expected_eoc);
  cfg=$fopen({root,"/case.txt"},"r"); image_fd=$fopen({root,"/image.img"},"rb");
  golden_fd=$fopen({root,"/expected.hex"},"r");
  if(!cfg || !image_fd || !golden_fd) die("fixture open");
  rc=$fscanf(cfg,"%d %d %d %d %d %d",media_sectors,nfiles,want_mount,want_file,inject,target_lba);
  if(rc!=6) die("fixture header");
  for(i=0;i<nfiles;i=i+1) begin rc=$fscanf(cfg,"%d %d",assets[i],lengths[i]); if(rc!=2) die("fixture index"); end
  pulse_reset();
  if(inject==7) begin
   fork
    mount();
    begin wait(req_valid); wait(busy); repeat(30) @(negedge clk); pulse_reset(); end
   join_any
   disable fork;
   disable_fault=1; mount();
  end else mount();
  #1;
  if(want_mount!=0) begin
   if(!error_valid || error_code!=want_mount || mounted || file_count!=0) die("wrong mount error");
   $display("EXPECTED_MOUNT_ERROR code=%0d",error_code);
   if(inject==9 || inject==10 || inject==16 || inject==17) begin
    disable_fault=1; @(negedge clk); mount(); #1;
    if(!mount_done || !mounted || error_valid) die("remount after failure");
   end
  end else begin
   if(!mounted || !mount_done || file_count!=nfiles) die("mount/count");
   for(i=0;i<nfiles;i=i+1) begin
    @(negedge clk); index_slot=i; #1;wait(index_valid);#1;
    if(!index_valid || index_id!=assets[i] || index_size!=lengths[i]) die("sorted index");
   end
   if(inject==8 && nfiles>0) begin
    start_file(assets[0]); wait(data_valid); repeat(20) @(negedge clk); pulse_reset();
    disable_fault=1; mount(); #1;
    if(!mount_done || !mounted) die("remount after stream reset");
   end
   for(j=0;j<nfiles;j=j+1) begin
    start_file(assets[j]); read_file(lengths[j],j==0 ? want_file : 0);
    if(j==0 && want_file!=0) begin
     // Malformed chain remains malformed; injected failures must allow a clean reopen.
     if((inject>=1 && inject<=6) || inject>=11) begin
      disable_fault=1; $fclose(golden_fd); golden_fd=$fopen({root,"/expected.hex"},"r");
      start_file(assets[0]); read_file(lengths[0],0);
     end else begin
      // Skip unconsumed golden bytes before reading the next independent file.
      $fclose(golden_fd); golden_fd=$fopen({root,"/expected.hex"},"r");
      for(i=0;i<lengths[0];i=i+1) rc=$fscanf(golden_fd,"%h",rc);
     end
    end
   end
   start_file(9998); wait(error_valid); #1;
   if(error_code!=11) die("missing ID");
   // Reopen the first file after normal completion and a missing-ID error.
   if(nfiles>0 && want_file==0) begin
    $fclose(golden_fd); golden_fd=$fopen({root,"/expected.hex"},"r");
    start_file(assets[0]); read_file(lengths[0],0);
   end
  end
  repeat(5) @(negedge clk);
  if(expected_eoc>=0 && !(eoc_mask & (1<<expected_eoc))) die("EOC branch not covered");
  $display("FAT32_CASE_PASS max=%0d checked=%0d requests=%0d stale=%0d cancels=%0d fat_hits=%0d fat_misses=%0d eoc_mask=%02h",MAX_FILES,checked,requests,stale,cancels,fat_hits,fat_misses,eoc_mask);
  $fclose(image_fd); $fclose(golden_fd); $fclose(cfg); $finish;
 end
endmodule
