set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set sim_dir [file normalize [file join $repo_dir build bupt_riscv_sim]]
set proj_dir [file normalize [file join $sim_dir vivado]]
file mkdir $sim_dir
cd $sim_dir

create_project bupt_riscv_sim $proj_dir -part xc7a100tcsg324-1 -force
file copy -force [file join $repo_dir src bupt_riscv bupt_riscv_boot.mem] [file join $sim_dir bupt_riscv_boot.mem]
file mkdir [file join $proj_dir bupt_riscv_sim.sim sim_1 behav xsim]
file copy -force [file join $repo_dir src bupt_riscv bupt_riscv_boot.mem] [file join $proj_dir bupt_riscv_sim.sim sim_1 behav xsim bupt_riscv_boot.mem]

add_files [glob [file join $repo_dir src common *.v]]
add_files [glob [file join $repo_dir src bupt_riscv riscv_core *.v]]
foreach rtl [glob [file join $repo_dir src bupt_riscv *.v]] {
    if {[lsearch -exact {top.v clk_100_to_200.v mig_axi_adapter.v} [file tail $rtl]] < 0} {
        add_files $rtl
    }
}
add_files -fileset sim_1 [file join $repo_dir sim bupt_riscv_tb.v]
set_property top bupt_riscv_tb [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
restart
run all
set sim_log [file join $proj_dir bupt_riscv_sim.sim sim_1 behav xsim simulate.log]
if {[file exists $sim_log]} {
    set fh [open $sim_log r]
    set log_text [read $fh]
    close $fh
    if {[string first "Simulation Failed" $log_text] >= 0} {
        error "BUPT RISC-V simulation reported failure"
    }
    if {[string first "Simulation succeeded: BUPT RISC-V CPU verified" $log_text] < 0} {
        error "BUPT RISC-V simulation success marker not found"
    }
}
close_sim
puts "BUPT_RISCV_SIM_DONE"
