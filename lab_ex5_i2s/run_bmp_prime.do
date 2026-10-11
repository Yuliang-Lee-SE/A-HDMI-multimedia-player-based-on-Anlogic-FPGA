onerror {quit -code 1 -f}
onbreak {resume}
file mkdir scaler_sim_build/bmp_prime
vlib scaler_sim_build/bmp_prime/work
vmap bmp_prime scaler_sim_build/bmp_prime/work
vlog -work bmp_prime src/user_source/hdl_source/SD/bmp_read.v tb_bmp_prime.v
vsim -onfinish stop bmp_prime.tb_bmp_prime
run -all
if {[examine -radix decimal sim:/tb_bmp_prime/errors]!=0 || [examine -radix decimal sim:/tb_bmp_prime/completed]!=1} {error "BMP prime failed"}
quit -sim
puts "BMP PRIME COMPLETE"
