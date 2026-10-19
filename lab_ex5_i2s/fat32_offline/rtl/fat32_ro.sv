// Independently written offline prototype. No third-party implementation code.
module fat32_ro #(
 parameter integer MAX_FILES=32, MAX_CHAIN=1024, MAX_DIR_ENTRIES=4096,
 parameter integer IO_TIMEOUT=20000, STALL_TIMEOUT=20000,
 parameter integer SLOT_W=$clog2(MAX_FILES), COUNT_W=$clog2(MAX_FILES+1)
)(
 input wire clk, rst,
 input wire mount_valid, output wire mount_ready,
 input wire [31:0] media_sectors,
 output reg mounted, output reg mount_done,
 output reg [COUNT_W-1:0] file_count,
 input wire [SLOT_W-1:0] index_slot,
 output wire index_valid, output wire [13:0] index_id,
 output wire [31:0] index_size,
 input wire open_valid, output wire open_ready, input wire [13:0] open_id,
 output wire data_valid, input wire data_ready, output wire [7:0] data,
 output reg file_done, output reg error_valid, output reg [7:0] error_code,
 output wire req_valid, input wire req_ready, output reg [31:0] req_lba,
 output reg [31:0] req_tag,
 input wire [31:0] rsp_tag, input wire rsp_valid, input wire [7:0] rsp_data,
 input wire rsp_done, rsp_error,
 output reg cancel_valid, output reg [31:0] cancel_tag
);
 localparam IDLE=0, REQ=1, RECEIVE=2, LBA0=3, PART=4, BPB=5,
 DIR_READ=6, DIR_ENTRY=7, LOOKUP=8, INSERT=9, DIR_NEXT=10,
 FAT=11, FAT_VALUE=12, CHECK_CHAIN=13, CHAIN_ADD=14,
 OPEN_SEARCH=15, FILE_READ=16, STREAM=17, FILE_NEXT=18, PART_DONE=20;
 // Error codes are part of the documented interface.
 localparam FORMAT=1, BOUNDS=2, IO=3, TIMEOUT=4, PROTOCOL=5,
 LIMIT=6, DUPLICATE=7, CLUSTER=8, LOOP=9, SHORT=10, NOT_FOUND=11, STALL=12;
 reg [5:0] state, return_state;
 reg [7:0] sector[0:511], fat_cache[0:511];
 reg [13:0] ids[0:MAX_FILES-1];
 reg [31:0] starts[0:MAX_FILES-1], sizes[0:MAX_FILES-1];
 reg [27:0] visited[0:MAX_CHAIN-1];
 reg [31:0] media_limit, volume, part_size, total, fat_base, data_base, clusters;
 reg [7:0] spc;
 reg [31:0] current, next_cluster, remaining;
 reg [31:0] cached_lba;
 reg cache_valid, load_fat, is_file, from_mbr;
 reg [31:0] timer;
 reg [9:0] received;
 reg [8:0] pos;
 reg [7:0] sec_in_cluster;
 reg [31:0] chain_count, check_pos, entry_count;
 reg [COUNT_W-1:0] search_pos, insert_pos;
 reg [13:0] candidate_id, requested_id;
 reg [31:0] candidate_start, candidate_size;
 reg [2:0] part_no;
 reg found_part;
 integer b;
 `define U16(a) {sector[(a)+1],sector[(a)]}
 `define U32(a) {sector[(a)+3],sector[(a)+2],sector[(a)+1],sector[(a)]}
 integer mp,mq;
 reg mbr_bad_format,mbr_bad_bounds;
 // Validate every populated primary entry and every pair, independently of selection.
 always @* begin
  mbr_bad_format=0; mbr_bad_bounds=0;
  for(mp=0;mp<4;mp=mp+1) begin
   if(sector[450+mp*16]!=0) begin
    if((sector[446+mp*16]!=0 && sector[446+mp*16]!=8'h80) ||
       sector[450+mp*16]==8'hee || sector[450+mp*16]==8'h05 ||
       sector[450+mp*16]==8'h0f || sector[450+mp*16]==8'h85) mbr_bad_format=1;
    if(`U32(454+mp*16)==0 || `U32(458+mp*16)==0 ||
       ({32'b0,`U32(454+mp*16)}+{32'b0,`U32(458+mp*16)})>{32'b0,media_limit}) mbr_bad_bounds=1;
    for(mq=0;mq<mp;mq=mq+1) begin
     if(sector[450+mq*16]!=0 &&
       {32'b0,`U32(454+mp*16)}<({32'b0,`U32(454+mq*16)}+{32'b0,`U32(458+mq*16)}) &&
       {32'b0,`U32(454+mq*16)}<({32'b0,`U32(454+mp*16)}+{32'b0,`U32(458+mp*16)})) mbr_bad_bounds=1;
    end
   end
  end
 end
 // Explicit byte dependencies also work with older event-driven simulators.
 wire [63:0] overhead={32'b0,`U16(14)}+({56'b0,sector[16]}*{32'b0,`U32(36)});
 wire [63:0] bpb_total={32'b0,`U32(32)};
 wire [63:0] count_clusters=(sector[13]!=0 && bpb_total>=overhead) ?
                      (bpb_total-overhead)/{56'b0,sector[13]} : 0;
 wire [63:0] volume_end={32'b0,volume}+bpb_total;
 wire [63:0] fat_capacity={32'b0,`U32(36)}*128;
 wire [63:0] active_fat= {32'b0,volume}+{48'b0,`U16(14)}+
                    ((`U16(40)&16'h80) ? ({60'b0,sector[40][3:0]}*{32'b0,`U32(36)}) : 0);
 wire [63:0] cluster_lba={32'b0,data_base}+(({32'b0,current}-2)*{56'b0,spc})+sec_in_cluster;
 wire [31:0] fat_lba=fat_base+(current>>7);
 wire [8:0] fat_offset={current[6:0],2'b00};
 wire [27:0] fat_entry={fat_cache[fat_offset+3][3:0],fat_cache[fat_offset+2],fat_cache[fat_offset+1],fat_cache[fat_offset]};
 wire [31:0] entry_cluster={`U16(pos+20),`U16(pos+26)};
 wire short_name=sector[pos]>=8'h30 && sector[pos]<=8'h39 &&
  sector[pos+1]>=8'h30 && sector[pos+1]<=8'h39 &&
  sector[pos+2]>=8'h30 && sector[pos+2]<=8'h39 &&
  sector[pos+3]>=8'h30 && sector[pos+3]<=8'h39 &&
  sector[pos+4]==32 && sector[pos+5]==32 && sector[pos+6]==32 && sector[pos+7]==32 &&
  (sector[pos+8]|8'h20)==8'h62 && (sector[pos+9]|8'h20)==8'h6d && (sector[pos+10]|8'h20)==8'h70;
 wire [13:0] name_id=(sector[pos]-48)*1000+(sector[pos+1]-48)*100+
                       (sector[pos+2]-48)*10+sector[pos+3]-48;
 assign mount_ready=(state==IDLE);
 assign open_ready=(state==IDLE && mounted && !mount_valid);
 assign req_valid=(state==REQ);
 assign index_valid=mounted && index_slot<file_count;
 assign index_id=index_valid ? ids[index_slot] : 0;
 assign index_size=index_valid ? sizes[index_slot] : 0;
 assign data_valid=(state==STREAM);
 assign data=sector[pos];
 task automatic fail(input [7:0] code);
 begin
  error_valid<=1; error_code<=code; state<=IDLE;
  if(!is_file) begin mounted<=0; file_count<=0; end
  if(state==REQ || state==RECEIVE) begin cancel_valid<=1; cancel_tag<=req_tag; end
 end endtask
 task automatic read_sector(input [31:0] lba, input [5:0] resume, input fat_dest);
 begin
  if(req_tag==32'hffffffff) fail(LIMIT); // Never reuse a transaction tag before reset/flush.
  else if(lba>=media_limit) fail(BOUNDS);
  else begin req_lba<=lba; req_tag<=req_tag+1; load_fat<=fat_dest;
   if(fat_dest) cache_valid<=0; // Partial replacement must never retain the old cache tag.
   return_state<=resume; received<=0; timer<=0; state<=REQ; end
 end endtask
 always @(posedge clk) begin
  if(rst) begin
   state<=IDLE; mounted<=0; mount_done<=0; file_count<=0;
   file_done<=0; error_valid<=0; error_code<=0; cancel_valid<=0; cancel_tag<=0;
   req_tag<=0; req_lba<=0; timer<=0; received<=0; cache_valid<=0;
   is_file<=0; pos<=0; media_limit<=0;
  end else begin
   mount_done<=0; file_done<=0; error_valid<=0; cancel_valid<=0;
   case(state)
    IDLE: begin
     if(mount_valid) begin
      mounted<=0; file_count<=0; is_file<=0; cache_valid<=0;
      media_limit<=media_sectors; volume<=0; from_mbr<=0;
      // Initial request cannot use previous media_limit.
      if(req_tag==32'hffffffff) fail(LIMIT);
      else if(media_sectors==0) fail(BOUNDS);
      else begin req_lba<=0; req_tag<=req_tag+1; load_fat<=0;
       return_state<=LBA0; received<=0; timer<=0; state<=REQ; end
     end else if(open_valid && mounted) begin
      requested_id<=open_id; search_pos<=0; is_file<=1; state<=OPEN_SEARCH;
     end
    end
    REQ: begin
     if(req_ready) begin state<=RECEIVE; timer<=0; end
     else if(timer==IO_TIMEOUT-1) fail(TIMEOUT);
     else timer<=timer+1;
    end
    RECEIVE: begin
     // Absolute transaction deadline, including arbitrary gaps in the byte stream.
     timer<=timer+1;
     if(timer==IO_TIMEOUT-1) fail(TIMEOUT);
     else if(rsp_tag==req_tag) begin
      if(rsp_error) fail(IO);
      else if(rsp_valid && received>=512) fail(PROTOCOL);
      else begin
       if(rsp_valid) begin
        if(load_fat) fat_cache[received[8:0]]<=rsp_data;
        else sector[received[8:0]]<=rsp_data;
        received<=received+1;
       end
       if(rsp_done) begin
        if(received+(rsp_valid ? 1 : 0)!=512) fail(PROTOCOL);
        else begin
         if(load_fat) begin cached_lba<=req_lba; cache_valid<=1; end
         timer<=0; state<=return_state;
        end
       end
      end
     end
    end
    LBA0: begin
     if(`U16(510)!=16'haa55) fail(FORMAT);
     else if((sector[0]==8'heb && sector[2]==8'h90) || sector[0]==8'he9) state<=BPB;
     else begin part_no<=0; found_part<=0; state<=PART; end
    end
    PART: begin
     b=446+part_no*16;
     // Select first FAT32 primary slot; ordinary other primary types are skipped.
     if(mbr_bad_format) fail(FORMAT);
     else if(mbr_bad_bounds) fail(BOUNDS);
     else begin
      if((sector[b+4]==8'h0b || sector[b+4]==8'h0c) && !found_part) begin
       volume<=`U32(b+8); part_size<=`U32(b+12); found_part<=1;
      end
      if(part_no==3) begin
       if(!found_part && sector[b+4]!=8'h0b && sector[b+4]!=8'h0c) fail(FORMAT);
       else state<=PART_DONE;
      end else part_no<=part_no+1;
     end
    end
    PART_DONE: begin from_mbr<=1; read_sector(volume,BPB,0); end
    BPB: begin
     if(`U16(510)!=16'haa55 || !((sector[0]==8'heb && sector[2]==8'h90)||sector[0]==8'he9) ||
       `U16(11)!=512 || sector[13]==0 || sector[13]>64 || (sector[13]&(sector[13]-1))!=0 ||
       `U16(14)==0 || (sector[16]!=1 && sector[16]!=2) || `U16(17)!=0 || `U16(19)!=0 ||
       `U16(22)!=0 || `U32(36)==0 || `U16(42)!=0 ||
       (`U16(40)&16'hff70)!=0 || ((`U16(40)&16'h80)!=0 && sector[40][3:0]>=sector[16])) fail(FORMAT);
     else if(bpb_total<=overhead || count_clusters<65525 || count_clusters>28'hfffffee ||
       fat_capacity<count_clusters+2 || volume_end>{32'b0,media_limit} ||
       volume_end>64'hffffffff || (from_mbr && bpb_total>{32'b0,part_size}) ||
       `U32(44)<2 || {32'b0,`U32(44)}>count_clusters+1) fail(BOUNDS);
     else begin
      spc<=sector[13]; total<=`U32(32); clusters<=count_clusters[31:0];
      fat_base<=active_fat[31:0]; data_base<=volume+overhead[31:0];
      current<=`U32(44); visited[0]<=`U32(44); chain_count<=1;
      sec_in_cluster<=0; entry_count<=0; state<=DIR_READ;
     end
    end
    DIR_READ, FILE_READ: begin
     if(current<2 || current>clusters+1 || current>=32'h0ffffff0 ||
        cluster_lba>={32'b0,volume}+total || cluster_lba>32'hffffffff) fail(CLUSTER);
     else read_sector(cluster_lba[31:0], is_file ? STREAM : DIR_ENTRY,0);
     pos<=0; timer<=0;
    end
    DIR_ENTRY: begin
     if(entry_count>=MAX_DIR_ENTRIES) fail(LIMIT);
     else if(sector[pos]==0) begin mounted<=1; mount_done<=1; state<=IDLE; end
     else begin
      entry_count<=entry_count+1;
      if(sector[pos]!=8'he5 && (sector[pos+11]&8'hd8)==0 && short_name && name_id!=0) begin
       if((entry_cluster<2 || entry_cluster>clusters+1 || entry_cluster>=32'h0ffffff0) &&
           !(`U32(pos+28)==0 && entry_cluster==0)) fail(CLUSTER);
       else begin candidate_id<=name_id; candidate_start<=entry_cluster;
        candidate_size<=`U32(pos+28); search_pos<=0; state<=LOOKUP; end
      end else state<=DIR_NEXT;
     end
    end
    LOOKUP: begin
     if(search_pos<file_count && ids[search_pos]==candidate_id) fail(DUPLICATE);
     else if(search_pos==file_count || ids[search_pos]>candidate_id) begin
      if(file_count==MAX_FILES) fail(LIMIT);
      else begin insert_pos<=file_count; state<=INSERT; end
     end else search_pos<=search_pos+1;
    end
    INSERT: begin
     if(insert_pos>search_pos) begin
      ids[insert_pos]<=ids[insert_pos-1]; starts[insert_pos]<=starts[insert_pos-1];
      sizes[insert_pos]<=sizes[insert_pos-1]; insert_pos<=insert_pos-1;
     end else begin
      ids[insert_pos]<=candidate_id; starts[insert_pos]<=candidate_start; sizes[insert_pos]<=candidate_size;
      file_count<=file_count+1; state<=DIR_NEXT;
     end
    end
    DIR_NEXT: begin
     if(pos==480) begin
      pos<=0;
      if(sec_in_cluster==spc-1) begin state<=FAT; end
      else begin sec_in_cluster<=sec_in_cluster+1; state<=DIR_READ; end
     end else begin pos<=pos+32; state<=DIR_ENTRY; end
    end
    FAT: begin
     if(cache_valid && cached_lba==fat_lba) state<=FAT_VALUE;
     else read_sector(fat_lba,FAT_VALUE,1);
    end
    FAT_VALUE: begin
     if(fat_entry>=28'hffffff8) begin
      if(is_file) fail(SHORT);
      else begin mounted<=1; mount_done<=1; state<=IDLE; end
     end else if(fat_entry<2 || fat_entry>=28'hffffff0 || fat_entry>clusters+1) fail(CLUSTER);
     else if(chain_count>=MAX_CHAIN) fail(LIMIT);
     else begin next_cluster<={4'b0,fat_entry}; check_pos<=0; state<=CHECK_CHAIN; end
    end
    CHECK_CHAIN: begin
     if(visited[check_pos]==next_cluster[27:0]) fail(LOOP);
     else if(check_pos+1==chain_count) state<=CHAIN_ADD;
     else check_pos<=check_pos+1;
    end
    CHAIN_ADD: begin
     visited[chain_count]<=next_cluster[27:0]; chain_count<=chain_count+1;
     current<=next_cluster; sec_in_cluster<=0; state<=is_file ? FILE_READ : DIR_READ;
    end
    OPEN_SEARCH: begin
     if(search_pos==file_count) fail(NOT_FOUND);
     else if(ids[search_pos]==requested_id) begin
      current<=starts[search_pos]; remaining<=sizes[search_pos];
      chain_count<=1; visited[0]<=starts[search_pos][27:0]; sec_in_cluster<=0;
      if(sizes[search_pos]==0) begin file_done<=1; state<=IDLE; end
      else state<=FILE_READ;
     end else search_pos<=search_pos+1;
    end
    STREAM: begin
     if(data_ready) begin
      timer<=0; remaining<=remaining-1;
      if(remaining==1) begin file_done<=1; state<=IDLE; end
      else if(pos==511) state<=FILE_NEXT;
      else pos<=pos+1;
     end else if(timer==STALL_TIMEOUT-1) fail(STALL);
     else timer<=timer+1;
    end
    FILE_NEXT: begin
     if(sec_in_cluster==spc-1) state<=FAT;
     else begin sec_in_cluster<=sec_in_cluster+1; state<=FILE_READ; end
    end
    default: fail(PROTOCOL);
   endcase
  end
 end
`undef U16
`undef U32
endmodule
