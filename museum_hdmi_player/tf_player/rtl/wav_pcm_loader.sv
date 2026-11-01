`timescale 1ns/1ps
// Parse a canonical 44-byte PCM WAV and write mono 16-bit samples into the
// audio RAM. The build workflow guarantees 8 kHz mono signed 16-bit files.
module wav_pcm_loader #(
    parameter integer RAM_DEPTH = 24576
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        data_valid,
    output wire        data_ready,
    input  wire [7:0]  data,
    input  wire        file_done,
    input  wire        file_error,
    output reg         ram_we,
    output reg [14:0]  ram_addr,
    output reg [15:0]  ram_data,
    output reg         done,
    output reg         error,
    output reg [15:0]  sample_count,
    output wire        busy
);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_HEADER = 3'd1;
    localparam [2:0] ST_CHECK = 3'd2;
    localparam [2:0] ST_LOW = 3'd3;
    localparam [2:0] ST_HIGH = 3'd4;
    localparam [2:0] ST_END = 3'd5;

    reg [2:0] state;
    reg [5:0] header_pos;
    reg [31:0] riff_id, wave_id, fmt_id, data_id;
    reg [31:0] sample_rate, byte_rate, data_bytes;
    reg [15:0] format_code, channels, block_align, bits_per_sample;
    reg [7:0] low_byte;
    reg [15:0] word_index;
    reg [15:0] expected_words;
    reg data_complete;

    assign busy = state != ST_IDLE;
    assign data_ready = (state == ST_HEADER) ||
                        (state == ST_LOW) ||
                        (state == ST_HIGH) ||
                        (state == ST_END);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= ST_IDLE;
            header_pos     <= 6'd0;
            riff_id        <= 32'd0;
            wave_id        <= 32'd0;
            fmt_id         <= 32'd0;
            data_id        <= 32'd0;
            sample_rate    <= 32'd0;
            byte_rate      <= 32'd0;
            data_bytes     <= 32'd0;
            format_code    <= 16'd0;
            channels       <= 16'd0;
            block_align    <= 16'd0;
            bits_per_sample<= 16'd0;
            low_byte       <= 8'd0;
            word_index     <= 16'd0;
            expected_words <= 16'd0;
            data_complete  <= 1'b0;
            ram_we         <= 1'b0;
            ram_addr       <= 15'd0;
            ram_data       <= 16'd0;
            done           <= 1'b0;
            error          <= 1'b0;
            sample_count   <= 16'd0;
        end else begin
            ram_we <= 1'b0;
            done   <= 1'b0;

            if (start) begin
                state          <= ST_HEADER;
                header_pos     <= 6'd0;
                riff_id        <= 32'd0;
                wave_id        <= 32'd0;
                fmt_id         <= 32'd0;
                data_id        <= 32'd0;
                sample_rate    <= 32'd0;
                byte_rate      <= 32'd0;
                data_bytes     <= 32'd0;
                format_code    <= 16'd0;
                channels       <= 16'd0;
                block_align    <= 16'd0;
                bits_per_sample<= 16'd0;
                low_byte       <= 8'd0;
                word_index     <= 16'd0;
                expected_words <= 16'd0;
                data_complete  <= 1'b0;
                sample_count   <= 16'd0;
                error          <= 1'b0;
            end else begin
                case (state)
                    ST_HEADER: begin
                        if (data_valid && data_ready) begin
                            if (header_pos < 6'd4)
                                riff_id <= {data,riff_id[31:8]};
                            else if (header_pos >= 6'd8 && header_pos < 6'd12)
                                wave_id <= {data,wave_id[31:8]};
                            else if (header_pos >= 6'd12 && header_pos < 6'd16)
                                fmt_id <= {data,fmt_id[31:8]};
                            else if (header_pos >= 6'd20 && header_pos < 6'd22)
                                format_code <= {data,format_code[15:8]};
                            else if (header_pos >= 6'd22 && header_pos < 6'd24)
                                channels <= {data,channels[15:8]};
                            else if (header_pos >= 6'd24 && header_pos < 6'd28)
                                sample_rate <= {data,sample_rate[31:8]};
                            else if (header_pos >= 6'd28 && header_pos < 6'd32)
                                byte_rate <= {data,byte_rate[31:8]};
                            else if (header_pos >= 6'd32 && header_pos < 6'd34)
                                block_align <= {data,block_align[15:8]};
                            else if (header_pos >= 6'd34 && header_pos < 6'd36)
                                bits_per_sample <= {data,bits_per_sample[15:8]};
                            else if (header_pos >= 6'd36 && header_pos < 6'd40)
                                data_id <= {data,data_id[31:8]};
                            else if (header_pos >= 6'd40)
                                data_bytes <= {data,data_bytes[31:8]};
                            if (header_pos == 6'd43)
                                state <= ST_CHECK;
                            else
                                header_pos <= header_pos + 6'd1;
                        end else if (file_error || file_done) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                            state <= ST_IDLE;
                        end
                    end

                    ST_CHECK: begin
                        if (file_error || file_done) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                            state <= ST_IDLE;
                        end else if (riff_id != 32'h46464952 ||
                            wave_id != 32'h45564157 ||
                            fmt_id != 32'h20746d66 ||
                            data_id != 32'h61746164 ||
                            format_code != 16'd1 || channels != 16'd1 ||
                            sample_rate != 32'd8000 || byte_rate != 32'd16000 ||
                            block_align != 16'd2 || bits_per_sample != 16'd16 ||
                            data_bytes == 32'd0 || (data_bytes & 32'd1) != 0 ||
                            (data_bytes >> 1) > RAM_DEPTH) begin
                            error <= 1'b1;
                            state <= ST_END;
                        end else begin
                            expected_words <= data_bytes >> 1;
                            state <= ST_LOW;
                        end
                    end

                    ST_LOW: begin
                        if (data_valid && data_ready) begin
                            low_byte <= data;
                            state <= ST_HIGH;
                        end else if (file_error || file_done) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                            state <= ST_IDLE;
                        end
                    end

                    ST_HIGH: begin
                        if (data_valid) begin
                            ram_we   <= 1'b1;
                            ram_addr <= word_index[14:0];
                            ram_data <= {data,low_byte};
                            sample_count <= sample_count + 16'd1;
                            if (word_index + 16'd1 >= expected_words) begin
                                word_index <= word_index + 16'd1;
                                data_complete <= 1'b1;
                                if (file_done) begin
                                    done <= 1'b1;
                                    state <= ST_IDLE;
                                end else begin
                                    state <= ST_END;
                                end
                            end else begin
                                word_index <= word_index + 16'd1;
                                state <= ST_LOW;
                            end
                        end else if (file_error || file_done) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                            state <= ST_IDLE;
                        end
                    end

                    ST_END: begin
                        // FAT asserts file_done one clock after consuming the
                        // final byte. Stay here and drain any malformed suffix
                        // so the shared file stream never stalls indefinitely.
                        if (file_error || (file_done && !data_complete))
                            error <= 1'b1;
                        if (file_done || file_error) begin
                            done  <= 1'b1;
                            state <= ST_IDLE;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
