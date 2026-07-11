set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set sim_dir [file normalize [file join $repo_dir build bupt_riscv_sim]]
set proj_dir [file normalize [file join $sim_dir vivado]]
set common_files [glob -nocomplain [file join $repo_dir src common *.v]]
set core_files [glob -nocomplain [file join $repo_dir src bupt_riscv riscv_core *.v]]
set soc_files [glob -nocomplain [file join $repo_dir src bupt_riscv *.v]]
if {[llength $common_files] == 0} {
    error "No UART/common RTL found under src/common/*.v"
}
if {[llength $core_files] == 0} {
    error "No RISC-V core RTL found under src/bupt_riscv/riscv_core/*.v"
}
if {[llength $soc_files] == 0} {
    error "No SoC RTL found under src/bupt_riscv/*.v"
}
file mkdir $sim_dir
cd $sim_dir

create_project bupt_riscv_sim $proj_dir -part xc7a100tcsg324-1 -force
file copy -force [file join $repo_dir src bupt_riscv bupt_riscv_boot.mem] [file join $sim_dir bupt_riscv_boot.mem]
file mkdir [file join $proj_dir bupt_riscv_sim.sim sim_1 behav xsim]
file copy -force [file join $repo_dir src bupt_riscv bupt_riscv_boot.mem] [file join $proj_dir bupt_riscv_sim.sim sim_1 behav xsim bupt_riscv_boot.mem]

add_files $common_files
add_files $core_files
foreach rtl $soc_files {
    if {[lsearch -exact {top.v clock_gen.v mig_axi_adapter.v} [file tail $rtl]] < 0} {
        add_files $rtl
    }
}
set sim_files [glob -nocomplain [file join $repo_dir sim *.v]]
if {[llength $sim_files] == 0} {
    error "No simulation testbenches found under sim/*.v"
}
add_files -fileset sim_1 $sim_files
update_compile_order -fileset sim_1

proc run_tb {proj_dir tb_name success_marker} {
    set_property top $tb_name [get_filesets sim_1]
    launch_simulation -simset sim_1 -mode behavioral
    restart
    run all
    close_sim
    set sim_log [file join $proj_dir bupt_riscv_sim.sim sim_1 behav xsim simulate.log]
    if {![file exists $sim_log]} {
        error "Simulation log not found for $tb_name: $sim_log"
    }
    set fh [open $sim_log r]
    set log_text [read $fh]
    close $fh
    if {[string first "Simulation Failed" $log_text] >= 0} {
        error "Simulation reported failure for $tb_name"
    }
    if {[string first $success_marker $log_text] < 0} {
        error "Simulation success marker not found for $tb_name"
    }
}

set tests {
    {bupt_riscv_acceptance_tb {Simulation succeeded: enhanced acceptance UART verified}}
    {bupt_riscv_tb {Simulation succeeded: BUPT RISC-V CPU verified}}
    {bupt_riscv_demo_tb {Simulation succeeded: pipeline demo stepping verified}}
    {bupt_riscv_scenarios_tb {Simulation succeeded: enhanced pipeline scenarios verified}}
    {pipeline_demo_panel_tb {Simulation succeeded: pipeline demo panel verified}}
    {acceptance_mmio_tb {Simulation succeeded: acceptance MMIO verified}}
}
foreach test $tests {
    lassign $test tb_name success_marker
    if {![info exists env(BUPT_RISCV_SIM_ONLY)] ||
        $env(BUPT_RISCV_SIM_ONLY) eq "" ||
        $env(BUPT_RISCV_SIM_ONLY) eq $tb_name} {
        run_tb $proj_dir $tb_name $success_marker
    }
}
puts "BUPT_RISCV_SIM_DONE"
