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
 localparam integer STATE_W=51;
 // Explicit one-hot control avoids decoding binary dynamic return states.
 localparam [STATE_W-1:0] IDLE=(51'b1<<0),
 REQ=(51'b1<<1),
 RECEIVE=(51'b1<<2),
 LBA0=(51'b1<<3),
 PART=(51'b1<<4),
 BPB=(51'b1<<5),
 DIR_READ=(51'b1<<6),
 DIR_ENTRY=(51'b1<<7),
 LOOKUP=(51'b1<<8),
 INSERT=(51'b1<<9),
 DIR_NEXT=(51'b1<<10),
 FAT=(51'b1<<11),
 FAT_VALUE=(51'b1<<12),
 CHECK_CHAIN=(51'b1<<13),
 CHAIN_ADD=(51'b1<<14),
 OPEN_SEARCH=(51'b1<<15),
 FILE_READ=(51'b1<<16),
 STREAM=(51'b1<<17),
 FILE_NEXT=(51'b1<<18),
 PART_DONE=(51'b1<<20),
 CHAIN_WAIT=(51'b1<<21),
 FAT_READ=(51'b1<<22),
 DIR_BEGIN=(51'b1<<23),
 DIR_WAIT=(51'b1<<24),
 DIR_CAPTURE=(51'b1<<25),
 STREAM_WAIT=(51'b1<<26),
 LOOKUP_WAIT=(51'b1<<27),
 INSERT_WAIT=(51'b1<<28),
 OPEN_WAIT=(51'b1<<29),
 INSERT_WRITE=(51'b1<<30),
 BPB_SUM=(51'b1<<31),
 BPB_DIFF=(51'b1<<32),
 BPB_SHIFT=(51'b1<<33),
 BPB_PLUS=(51'b1<<34),
 BPB_TEST=(51'b1<<35),
 BPB_ACCEPT=(51'b1<<36),
 READ_SHIFT=(51'b1<<37),
 READ_ADD=(51'b1<<38),
 READ_SECTOR=(51'b1<<39),
 READ_CHECK=(51'b1<<40),
 MBR_LATCH=(51'b1<<41),
 FAT_LATCH=(51'b1<<42),
 DIR_DECIDE=(51'b1<<43),
 DIR_VALIDATE=(51'b1<<44),
 FAT_FLAGS=(51'b1<<45),
 CHAIN_COMPARE=(51'b1<<46),
 MBR_SUM=(51'b1<<47),
 LOOKUP_COMPARE=(51'b1<<48),
 OPEN_COMPARE=(51'b1<<49),
 BPB_FORMAT_RESULT=(51'b1<<50);
 // Error codes are part of the documented interface.
 localparam FORMAT=1, BOUNDS=2, IO=3, TIMEOUT=4, PROTOCOL=5,
 LIMIT=6, DUPLICATE=7, CLUSTER=8, LOOP=9, SHORT=10, NOT_FOUND=11, STALL=12;
 reg [STATE_W-1:0] state, return_state;
 reg [7:0] sector[0:511];
 reg [7:0] entry_bytes[0:31];
 reg [383:0] header_shift;
 reg [127:0] mbr_e0,mbr_e1,mbr_e2,mbr_e3;
 reg header_we,mbr_we;reg [7:0] header_data,mbr_data;reg [1:0] mbr_part;
 reg [15:0] signature;
 reg [7:0] sector_q;reg [4:0] entry_byte;
 reg [31:0] fat_cache[0:127];
 reg [31:0] fat_word,rx_word;
 reg [77:0] index_mem[0:MAX_FILES-1];
 reg [77:0] index_q,table_q,index_wdata;
 reg [SLOT_W-1:0] index_slot_q,index_waddr;
 reg index_we;
 localparam CHAIN_AW=(MAX_CHAIN>1) ? $clog2(MAX_CHAIN):1;
 reg [27:0] visited[0:MAX_CHAIN-1];
 reg visited_we;
 reg [CHAIN_AW-1:0] visited_waddr;
 reg [27:0] visited_wdata,visited_q;
 reg [31:0] media_limit, volume, part_size, total, fat_base, data_base, clusters;
 reg [7:0] spc;
 reg [31:0] current, next_cluster, remaining;
 reg [31:0] cached_lba;
 reg cache_valid, load_fat, is_file, from_mbr;
 reg [31:0] timer;
 reg [9:0] received;
 reg [8:0] pos;
 reg [7:0] sec_in_cluster;
 reg [$clog2(MAX_CHAIN+1)-1:0] chain_count;
 reg [CHAIN_AW-1:0] check_pos;
 reg [31:0] entry_count;
 reg [COUNT_W-1:0] search_pos, insert_pos;
 reg [13:0] candidate_id, requested_id;
 reg [31:0] candidate_start, candidate_size;
 reg [2:0] part_no;
 reg found_part;
 integer b;
 wire [5:0] mbr_offset=received[5:0]+6'd2;
 // Only fixed metadata windows are shifted. Each response byte drives a few
 // local registers, instead of a multiport distributed-RAM write bus.
 always @(posedge clk) begin
  if(header_we) header_shift<={header_data,header_shift[383:8]};
  if(mbr_we) case(mbr_part)
   0:mbr_e0<={mbr_data,mbr_e0[127:8]};1:mbr_e1<={mbr_data,mbr_e1[127:8]};
   2:mbr_e2<={mbr_data,mbr_e2[127:8]};3:mbr_e3<={mbr_data,mbr_e3[127:8]};
  endcase
 end
 function automatic [7:0] header_byte(input [5:0] n);
  header_byte=header_shift[{n,3'b0}+:8];
 endfunction
 function automatic [7:0] mbr_byte(input [5:0] n);
  case(n[5:4])
   0:mbr_byte=mbr_e0[{n[3:0],3'b0}+:8];1:mbr_byte=mbr_e1[{n[3:0],3'b0}+:8];
   2:mbr_byte=mbr_e2[{n[3:0],3'b0}+:8];3:mbr_byte=mbr_e3[{n[3:0],3'b0}+:8];
  endcase
 endfunction
 reg [27:0] fat_entry_latched;
 reg fat_is_eoc,fat_is_bad,fat_at_limit;
 reg visited_match,visited_last;
 reg dir_candidate,dir_cluster_bad;
 reg [6:0] name_hi,name_lo;
 reg [13:0] dir_id;
 reg [31:0] dir_start,dir_size;
 reg [15:0] bpb_reserved;
 reg [31:0] bpb_fatsize,bpb_total_reg,bpb_root;
 reg [7:0] bpb_spc,bpb_nfats;
 reg bpb_active,bpb_bounds1,bpb_bounds2,bpb_bounds3,bpb_short;
 reg [33:0] bpb_overhead,bpb_usable,bpb_clusters,bpb_fatbase;
 reg [32:0] bpb_volume_end,bpb_active_offset;
 reg [38:0] bpb_fat_capacity;
 reg [34:0] bpb_cluster_limit,bpb_capacity_needed,bpb_database;
 reg [31:0] volume_limit,cluster_limit;
 reg [2:0] spc_shift;
 reg [27:0] cluster_offset;
 reg [34:0] cluster_sector_offset,sector_lba;
 reg mbr_format_q,mbr_bounds_q;
 reg [32:0] mbr_end[0:3];
 reg table_equal,table_greater,table_empty;
 reg search_at_end,search_before_end,index_full;
 reg [3:0] bpb_bad;

 wire [SLOT_W-1:0] table_addr=((|(state & INSERT)) || (|(state & INSERT_WAIT)) || (|(state & INSERT_WRITE))) ?
                            (insert_pos-1'b1):search_pos;
 wire [SLOT_W-1:0] table_port_addr=index_we ? index_waddr:table_addr;
 wire [13:0] table_id=table_q[77:64];
 wire [31:0] table_start=table_q[63:32],table_size=table_q[31:0];
 wire [8:0] sector_addr=((|(state & DIR_BEGIN)) || (|(state & DIR_WAIT)) || (|(state & DIR_CAPTURE))) ? pos+entry_byte:pos;

 // One synchronous read and one write port, no memory reset or initial data.
 always @(posedge clk) begin
  if(visited_we) visited[visited_waddr]<=visited_wdata;
  visited_q<=visited[check_pos];
  fat_word<=fat_cache[current[6:0]];
  sector_q<=sector[sector_addr];
  index_q<=index_mem[index_slot];index_slot_q<=index_slot;
  if(index_we) index_mem[table_port_addr]<=index_wdata;
  table_q<=index_mem[table_port_addr];
 end
 `define U16(a) {header_byte((a)+1),header_byte((a))}
 `define E16(a) {entry_bytes[(a)+1],entry_bytes[(a)]}
 `define U32(a) {header_byte((a)+3),header_byte((a)+2),header_byte((a)+1),header_byte((a))}
 `define E32(a) {entry_bytes[(a)+3],entry_bytes[(a)+2],entry_bytes[(a)+1],entry_bytes[(a)]}
 `define M32(a) {mbr_byte((a)+3),mbr_byte((a)+2),mbr_byte((a)+1),mbr_byte((a))}
 integer mp,mq;
 reg mbr_bad_format,mbr_bad_bounds;
 // Validate every populated primary entry and every pair, independently of selection.
 always @(mbr_e0 or mbr_e1 or mbr_e2 or mbr_e3 or media_limit or mbr_end[0] or mbr_end[1] or mbr_end[2] or mbr_end[3]) begin
  mbr_bad_format=0; mbr_bad_bounds=0;
  for(mp=0;mp<4;mp=mp+1) begin
   if(mbr_byte(4+mp*16)!=0) begin
    if((mbr_byte(0+mp*16)!=0 && mbr_byte(0+mp*16)!=8'h80) ||
       mbr_byte(4+mp*16)==8'hee || mbr_byte(4+mp*16)==8'h05 ||
       mbr_byte(4+mp*16)==8'h0f || mbr_byte(4+mp*16)==8'h85) mbr_bad_format=1;
    if(`M32(8+mp*16)==0 || `M32(12+mp*16)==0 ||
       mbr_end[mp]>{1'b0,media_limit}) mbr_bad_bounds=1;
    for(mq=0;mq<mp;mq=mq+1) begin
     if(mbr_byte(4+mq*16)!=0 &&
       {1'b0,`M32(8+mp*16)}<mbr_end[mq] &&
       {1'b0,`M32(8+mq*16)}<mbr_end[mp]) mbr_bad_bounds=1;
    end
   end
  end
 end
 function automatic [2:0] cluster_shift(input [7:0] size);
 begin case(size) 2:cluster_shift=1;4:cluster_shift=2;8:cluster_shift=3;
  16:cluster_shift=4;32:cluster_shift=5;64:cluster_shift=6;default:cluster_shift=0;endcase end
 endfunction
 // Metadata calculations are staged so validation does not drive a long
 // add/subtract/shift/compare chain into the state and RAM write enables.
 reg [31:0] fat_lba;
 always @(posedge clk) fat_lba<=fat_base+(current>>7);
 wire [63:0] cluster_lba={29'b0,sector_lba};
 wire [8:0] fat_offset={current[6:0],2'b00};
 wire [27:0] fat_entry=fat_entry_latched;
 wire [31:0] entry_cluster={`E16(20),`E16(26)};
 wire short_name=entry_bytes[0]>=8'h30 && entry_bytes[0]<=8'h39 &&
  entry_bytes[1]>=8'h30 && entry_bytes[1]<=8'h39 &&
  entry_bytes[2]>=8'h30 && entry_bytes[2]<=8'h39 &&
  entry_bytes[3]>=8'h30 && entry_bytes[3]<=8'h39 &&
  entry_bytes[4]==32 && entry_bytes[5]==32 && entry_bytes[6]==32 && entry_bytes[7]==32 &&
  (entry_bytes[8]|8'h20)==8'h62 && (entry_bytes[9]|8'h20)==8'h6d && (entry_bytes[10]|8'h20)==8'h70;
 wire [13:0] name_id=name_hi*14'd100+name_lo;
 assign mount_ready=((|(state & IDLE)));
 assign open_ready=((|(state & IDLE)) && mounted && !mount_valid);
 assign req_valid=((|(state & REQ)));
 assign index_valid=mounted && index_slot<file_count && index_slot_q==index_slot;
 assign index_id=index_valid ? index_q[77:64] : 0;
 assign index_size=index_valid ? index_q[31:0] : 0;
 assign data_valid=((|(state & STREAM)));
 assign data=sector_q;
 task automatic fail(input [7:0] code);
 begin
  error_valid<=1; error_code<=code; state<=IDLE;
  if(!is_file) begin mounted<=0; file_count<=0; end
  if((|(state & REQ)) || (|(state & RECEIVE))) begin cancel_valid<=1; cancel_tag<=req_tag; end
 end endtask
 task automatic read_sector(input [31:0] lba, input [STATE_W-1:0] resume, input fat_dest);
 begin
  if(req_tag==32'hffffffff) fail(LIMIT); // Never reuse a transaction tag before reset/flush.
  else if(lba>=media_limit) fail(BOUNDS);
  else begin req_lba<=lba; req_tag<=req_tag+1; load_fat<=fat_dest;
   if(fat_dest) cache_valid<=0; // Partial replacement must never retain the old cache tag.
   return_state<=resume; received<=0; timer<=0; state<=REQ; end
 end endtask
 always @(posedge clk) begin
  if(rst) begin
   state<=IDLE; mounted<=0; mount_done<=0; file_count<=0;visited_we<=0;index_we<=0;header_we<=0;mbr_we<=0;
   file_done<=0; error_valid<=0; error_code<=0; cancel_valid<=0; cancel_tag<=0;
   req_tag<=0; req_lba<=0; timer<=0; received<=0; cache_valid<=0;
   is_file<=0; pos<=0; media_limit<=0;
  end else begin
   mount_done<=0; file_done<=0; error_valid<=0; cancel_valid<=0;visited_we<=0;index_we<=0;header_we<=0;mbr_we<=0;
   case(1'b1) // synthesis parallel_case
    (|(state & IDLE)): begin
     if(mount_valid) begin
      mounted<=0; file_count<=0; is_file<=0; cache_valid<=0;
      media_limit<=media_sectors; volume<=0; from_mbr<=0;
      // Initial request cannot use previous media_limit.
      if(req_tag==32'hffffffff) fail(LIMIT);
      else if(media_sectors==0) fail(BOUNDS);
      else begin req_lba<=0; req_tag<=req_tag+1; load_fat<=0;
       return_state<=LBA0; received<=0; timer<=0; state<=REQ; end
     end else if(open_valid && mounted) begin
      requested_id<=open_id; search_pos<=0; is_file<=1; state<=OPEN_WAIT;
     end
    end
    (|(state & REQ)): begin
     if(req_ready) begin state<=RECEIVE; timer<=0; end
     else if(timer==IO_TIMEOUT-1) fail(TIMEOUT);
     else timer<=timer+1;
    end
    (|(state & RECEIVE)): begin
     // Absolute transaction deadline, including arbitrary gaps in the byte stream.
     timer<=timer+1;
     if(timer==IO_TIMEOUT-1) fail(TIMEOUT);
     else if(rsp_tag==req_tag) begin
      if(rsp_error) fail(IO);
      else if(rsp_valid && received>=512) fail(PROTOCOL);
      else begin
       if(rsp_valid) begin
        if(load_fat) begin
         rx_word<={rsp_data,rx_word[31:8]};
         if(received[1:0]==3) fat_cache[received[8:2]]<={rsp_data,rx_word[31:8]};
        end
        else begin
         sector[received[8:0]]<=rsp_data;
         if(received<48) begin header_data<=rsp_data;header_we<=1;end
         if(received>=446 && received<510) begin mbr_data<=rsp_data;mbr_part<=mbr_offset[5:4];mbr_we<=1;end
         if(received==510) signature[7:0]<=rsp_data;
         if(received==511) signature[15:8]<=rsp_data;
        end
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
    (|(state & LBA0)): begin
     if(signature!=16'haa55) fail(FORMAT);
     else if((header_byte(0)==8'heb && header_byte(2)==8'h90) || header_byte(0)==8'he9) state<=BPB;
     else begin part_no<=0; found_part<=0; state<=MBR_SUM; end
    end
    (|(state & MBR_SUM)): begin
     mbr_end[0]<={1'b0,`M32(8)}+{1'b0,`M32(12)};
     mbr_end[1]<={1'b0,`M32(24)}+{1'b0,`M32(28)};
     mbr_end[2]<={1'b0,`M32(40)}+{1'b0,`M32(44)};
     mbr_end[3]<={1'b0,`M32(56)}+{1'b0,`M32(60)};
     state<=MBR_LATCH;
    end
    (|(state & MBR_LATCH)): begin mbr_format_q<=mbr_bad_format;mbr_bounds_q<=mbr_bad_bounds;state<=PART;end
    (|(state & PART)): begin
     b=part_no*16;
     // Select first FAT32 primary slot; ordinary other primary types are skipped.
     if(mbr_format_q) fail(FORMAT);
     else if(mbr_bounds_q) fail(BOUNDS);
     else begin
      if((mbr_byte(b+4)==8'h0b || mbr_byte(b+4)==8'h0c) && !found_part) begin
       volume<=`M32(b+8); part_size<=`M32(b+12); found_part<=1;
      end
      if(part_no==3) begin
       if(!found_part && mbr_byte(b+4)!=8'h0b && mbr_byte(b+4)!=8'h0c) fail(FORMAT);
       else state<=PART_DONE;
      end else part_no<=part_no+1;
     end
    end
    (|(state & PART_DONE)): begin from_mbr<=1; read_sector(volume,BPB,0); end
    (|(state & BPB)): begin
     bpb_bad[0]<=signature!=16'haa55 || !((header_byte(0)==8'heb && header_byte(2)==8'h90)||header_byte(0)==8'he9) || `U16(11)!=512;
     bpb_bad[1]<=header_byte(13)==0 || header_byte(13)>64 || (header_byte(13)&(header_byte(13)-8'd1))!=0;
     bpb_bad[2]<=`U16(14)==0 || (header_byte(16)!=1 && header_byte(16)!=2) || `U16(17)!=0 || `U16(19)!=0 || `U16(22)!=0;
     bpb_bad[3]<=`U32(36)==0 || `U16(42)!=0 || (`U16(40)&16'hff70)!=0 ||
        ((header_byte(40)&8'h80)!=0 && (header_byte(40)&8'h0f)>=header_byte(16));
     bpb_reserved<=`U16(14);bpb_fatsize<=`U32(36);bpb_total_reg<=`U32(32);bpb_root<=`U32(44);
     bpb_spc<=header_byte(13);bpb_nfats<=header_byte(16);bpb_active<=((header_byte(40)&8'h80)!=0) && ((header_byte(40)&8'h01)!=0);
     state<=BPB_FORMAT_RESULT;
    end
    (|(state & BPB_FORMAT_RESULT)): if(|bpb_bad) fail(FORMAT);else state<=BPB_SUM;
    (|(state & BPB_SUM)): begin
     bpb_overhead<=({2'b0,bpb_fatsize} << (bpb_nfats==2 ? 1:0))+bpb_reserved;
     bpb_volume_end<={1'b0,volume}+{1'b0,bpb_total_reg};
     bpb_fat_capacity<={bpb_fatsize,7'b0};
     bpb_active_offset<=(bpb_active ? {1'b0,bpb_fatsize}:33'd0)+bpb_reserved;
     state<=BPB_DIFF;
    end
    (|(state & BPB_DIFF)): begin
     bpb_short<=({2'b0,bpb_total_reg}<=bpb_overhead);
     bpb_usable<={2'b0,bpb_total_reg}-bpb_overhead;
     bpb_fatbase<={2'b0,volume}+{1'b0,bpb_active_offset};
     bpb_database<={3'b0,volume}+{1'b0,bpb_overhead};state<=BPB_SHIFT;
    end
    (|(state & BPB_SHIFT)): begin
     bpb_clusters<=bpb_usable>>cluster_shift(bpb_spc);
     bpb_bounds1<=bpb_short || bpb_volume_end>{1'b0,media_limit} || bpb_volume_end>33'h0ffffffff ||
                  (from_mbr && bpb_total_reg>part_size);
     state<=BPB_PLUS;
    end
    (|(state & BPB_PLUS)): begin
     bpb_cluster_limit<={1'b0,bpb_clusters}+1'b1;
     bpb_capacity_needed<={1'b0,bpb_clusters}+2;
     bpb_bounds2<=bpb_clusters<65525 || bpb_clusters>28'hfffffee;state<=BPB_TEST;
    end
    (|(state & BPB_TEST)): begin
     bpb_bounds3<=bpb_fat_capacity<bpb_capacity_needed || bpb_root<2 || {3'b0,bpb_root}>bpb_cluster_limit;
     state<=BPB_ACCEPT;
    end
    (|(state & BPB_ACCEPT)): begin
     if(bpb_bounds1 || bpb_bounds2 || bpb_bounds3) fail(BOUNDS);
     else begin
      spc<=bpb_spc;spc_shift<=cluster_shift(bpb_spc);total<=bpb_total_reg;clusters<=bpb_clusters[31:0];
      volume_limit<=bpb_volume_end[31:0];cluster_limit<=bpb_cluster_limit[31:0];
      fat_base<=bpb_fatbase[31:0];data_base<=bpb_database[31:0];current<=bpb_root;
      visited_we<=1;visited_waddr<=0;visited_wdata<=bpb_root[27:0];chain_count<=1;
      sec_in_cluster<=0;entry_count<=0;state<=DIR_READ;
     end
    end
    (|(state & (DIR_READ|FILE_READ))): begin
     pos<=0;timer<=0;
     if(current<2 || current>cluster_limit || current>=32'h0ffffff0) fail(CLUSTER);
     else begin cluster_offset<=current[27:0]-28'd2;state<=READ_SHIFT;end
    end
    (|(state & READ_SHIFT)): begin cluster_sector_offset<={7'd0,cluster_offset}<<spc_shift;state<=READ_ADD;end
    (|(state & READ_ADD)): begin sector_lba<={3'd0,data_base}+cluster_sector_offset;state<=READ_SECTOR;end
    (|(state & READ_SECTOR)): begin sector_lba<=sector_lba+sec_in_cluster;state<=READ_CHECK;end
    (|(state & READ_CHECK)): begin
     if(sector_lba>={3'd0,volume_limit}) fail(CLUSTER);
     else read_sector(sector_lba[31:0],is_file ? STREAM:DIR_BEGIN,0);
    end
    (|(state & DIR_BEGIN)): begin entry_byte<=0;state<=DIR_WAIT;end
    (|(state & DIR_WAIT)): state<=DIR_CAPTURE;
    (|(state & DIR_CAPTURE)): begin
     entry_bytes[entry_byte]<=sector_q;
     if(entry_byte==31) state<=DIR_ENTRY;
     else begin entry_byte<=entry_byte+1'b1;state<=DIR_WAIT;end
    end
    (|(state & DIR_ENTRY)): begin
     if(entry_count>=MAX_DIR_ENTRIES) fail(LIMIT);
     else if(entry_bytes[0]==0) begin mounted<=1;mount_done<=1;state<=IDLE;end
     else begin
      entry_count<=entry_count+1;
      dir_candidate<=entry_bytes[0]!=8'he5 && (entry_bytes[11]&8'hd8)==0 && short_name &&
       (entry_bytes[0]!=8'h30 || entry_bytes[1]!=8'h30 || entry_bytes[2]!=8'h30 || entry_bytes[3]!=8'h30);
      dir_cluster_bad<=(entry_cluster<2 || entry_cluster>cluster_limit || entry_cluster>=32'h0ffffff0) &&
                       !(`E32(28)==0 && entry_cluster==0);
      dir_start<=entry_cluster;dir_size<=`E32(28);
      name_hi<=(entry_bytes[0]-8'd48)*7'd10+(entry_bytes[1]-8'd48);
      name_lo<=(entry_bytes[2]-8'd48)*7'd10+(entry_bytes[3]-8'd48);
      state<=DIR_DECIDE;
     end
    end
    (|(state & DIR_DECIDE)): begin dir_id<=name_id;state<=DIR_VALIDATE;end
    (|(state & DIR_VALIDATE)): begin
     if(dir_candidate) begin
      if(dir_cluster_bad) fail(CLUSTER);
      else begin candidate_id<=dir_id;candidate_start<=dir_start;candidate_size<=dir_size;
       search_pos<=0;state<=LOOKUP_WAIT;end
     end else state<=DIR_NEXT;
    end
    (|(state & LOOKUP_WAIT)): state<=LOOKUP_COMPARE;
    (|(state & LOOKUP_COMPARE)): begin
     table_equal<=table_id==candidate_id;table_greater<=table_id>candidate_id;
     search_at_end<=search_pos==file_count;search_before_end<=search_pos<file_count;index_full<=file_count==MAX_FILES;
     state<=LOOKUP;
    end
    (|(state & LOOKUP)): begin
     if(search_before_end && table_equal) fail(DUPLICATE);
     else if(search_at_end || table_greater) begin
      if(index_full) fail(LIMIT);
      else begin insert_pos<=file_count; state<=INSERT_WAIT; end
     end else begin search_pos<=search_pos+1;state<=LOOKUP_WAIT;end
    end
    (|(state & INSERT_WAIT)): state<=INSERT;
    (|(state & INSERT_WRITE)): state<=INSERT_WAIT;
    (|(state & INSERT)): begin
     index_we<=1;index_waddr<=insert_pos[SLOT_W-1:0];
     if(insert_pos>search_pos) begin
      index_wdata<=table_q;insert_pos<=insert_pos-1;state<=INSERT_WRITE;
     end else begin
      index_wdata<={candidate_id,candidate_start,candidate_size};
      file_count<=file_count+1;state<=DIR_NEXT;
     end
    end
    (|(state & DIR_NEXT)): begin
     if(pos==480) begin
      pos<=0;
      if(sec_in_cluster==spc-1) begin state<=FAT; end
      else begin sec_in_cluster<=sec_in_cluster+1; state<=DIR_READ; end
     end else begin pos<=pos+32; state<=DIR_BEGIN; end
    end
    (|(state & FAT)): begin
     if(cache_valid && cached_lba==fat_lba) state<=FAT_READ;
     else read_sector(fat_lba,FAT_READ,1);
    end
    (|(state & FAT_READ)): state<=FAT_LATCH; // Read after a possible same-cycle cache write.
    (|(state & FAT_LATCH)): begin fat_entry_latched<=fat_word[27:0];state<=FAT_FLAGS;end
    (|(state & FAT_FLAGS)): begin
     fat_is_eoc<=fat_entry>=28'hffffff8;
     fat_is_bad<=fat_entry<2 || fat_entry>=28'hffffff0 || fat_entry>cluster_limit;
     fat_at_limit<=chain_count>=MAX_CHAIN;state<=FAT_VALUE;
    end
    (|(state & FAT_VALUE)): begin
     if(fat_is_eoc) begin
      if(is_file) fail(SHORT);
      else begin mounted<=1; mount_done<=1; state<=IDLE; end
     end else if(fat_is_bad) fail(CLUSTER);
     else if(fat_at_limit) fail(LIMIT);
     else begin next_cluster<={4'b0,fat_entry}; check_pos<=0; state<=CHAIN_WAIT; end
    end
    (|(state & CHAIN_WAIT)): state<=CHAIN_COMPARE;
    (|(state & CHAIN_COMPARE)): begin
     visited_match<=visited_q==next_cluster[27:0];
     visited_last<=check_pos+1==chain_count;state<=CHECK_CHAIN;
    end
    (|(state & CHECK_CHAIN)): begin
     if(visited_match) fail(LOOP);
     else if(visited_last) state<=CHAIN_ADD;
     else begin check_pos<=check_pos+1;state<=CHAIN_WAIT;end
    end
    (|(state & CHAIN_ADD)): begin
     visited_we<=1;visited_waddr<=chain_count[CHAIN_AW-1:0];visited_wdata<=next_cluster[27:0];chain_count<=chain_count+1;
     current<=next_cluster; sec_in_cluster<=0; state<=is_file ? FILE_READ : DIR_READ;
    end
    (|(state & OPEN_WAIT)): state<=OPEN_COMPARE;
    (|(state & OPEN_COMPARE)): begin
     table_equal<=table_id==requested_id;table_empty<=table_size==0;search_at_end<=search_pos==file_count;state<=OPEN_SEARCH;
    end
    (|(state & OPEN_SEARCH)): begin
     if(search_at_end) fail(NOT_FOUND);
     else if(table_equal) begin
      current<=table_start; remaining<=table_size;
      chain_count<=1;visited_we<=1;visited_waddr<=0;visited_wdata<=table_start[27:0]; sec_in_cluster<=0;
      if(table_empty) begin file_done<=1; state<=IDLE; end
      else state<=FILE_READ;
     end else begin search_pos<=search_pos+1;state<=OPEN_WAIT;end
    end
    (|(state & STREAM)): begin
     if(data_ready) begin
      timer<=0; remaining<=remaining-1;
      if(remaining==1) begin file_done<=1; state<=IDLE; end
      else if(pos==511) state<=FILE_NEXT;
      else begin pos<=pos+1;state<=STREAM_WAIT;end
     end else if(timer==STALL_TIMEOUT-1) fail(STALL);
     else timer<=timer+1;
    end
    (|(state & STREAM_WAIT)): state<=STREAM;
    (|(state & FILE_NEXT)): begin
     if(sec_in_cluster==spc-1) state<=FAT;
     else begin sec_in_cluster<=sec_in_cluster+1; state<=FILE_READ; end
    end
    default: fail(PROTOCOL);
   endcase
  end
 end
`undef U16
`undef U32
`undef E16
`undef E32
`undef M32
endmodule
