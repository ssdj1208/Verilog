set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set build_name bupt_riscv_vivado
if {[info exists env(BUPT_RISCV_BUILD_NAME)] && $env(BUPT_RISCV_BUILD_NAME) ne ""} {
    set build_name $env(BUPT_RISCV_BUILD_NAME)
}
set proj_dir [file normalize [file join $repo_dir build $build_name]]
set bit_out  [file normalize [file join $repo_dir build bupt_riscv_top.bit]]
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

create_project bupt_riscv $proj_dir -part xc7a100tcsg324-1 -force

create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 -module_name lab10_mig
set_property -dict [list CONFIG.XML_INPUT_FILE [file join $repo_dir src bupt_riscv mig nexys4ddr_mig.prj]] [get_ips lab10_mig]
generate_target all [get_ips lab10_mig]

add_files $common_files
add_files $core_files
foreach rtl $soc_files {
    if {[file tail $rtl] ne "ddr_model.v"} {
        add_files $rtl
    }
}
add_files [file join $repo_dir src bupt_riscv bupt_riscv_boot.mem]
add_files -fileset constrs_1 [file join $repo_dir constr nexys4ddr_bupt_riscv.xdc]
set_property top top [current_fileset]
update_compile_order -fileset sources_1

set impl_run [get_runs impl_1]
foreach {prop value} {
    strategy Performance_ExplorePostRoutePhysOpt
    STEPS.OPT_DESIGN.ARGS.DIRECTIVE Explore
    STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore
    STEPS.PHYS_OPT_DESIGN.IS_ENABLED true
    STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore
    STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore
    STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true
    STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore
} {
    if {[catch {set_property $prop $value $impl_run} msg]} {
        puts "BUPT_RISCV_IMPL_OPTION_SKIPPED $prop=$value ($msg)"
    }
}

launch_runs synth_1 -jobs 16
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "BUPT RISC-V synthesis failed"
}

launch_runs impl_1 -to_step write_bitstream -jobs 16
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "BUPT RISC-V implementation/bitstream failed"
}

open_run impl_1

set fp_op_regs [get_cells -hier -regexp {.*soc/bus/fp/op_[ab]_reg\[[0-9]+\]}]
set fp_sel_regs [get_cells -hier -regexp {.*soc/bus/fp/op_sel_reg\[[0-9]+\]}]
set fp_result_regs [get_cells -hier -regexp {.*soc/bus/fp/result_reg_reg\[[0-9]+\]}]
if {[llength $fp_result_regs] > 0} {
    set fp_launch_pins [get_pins -of_objects [concat $fp_op_regs $fp_sel_regs] -filter {REF_PIN_NAME == C}]
    set fp_capture_pins [get_pins -of_objects $fp_result_regs -filter {REF_PIN_NAME == D}]
    puts "BUPT_RISCV_FP_MULTICYCLE launch=[llength $fp_launch_pins] capture=[llength $fp_capture_pins]"
    set_multicycle_path 3 -setup -from $fp_launch_pins -to $fp_capture_pins
    set_multicycle_path 2 -hold  -from $fp_launch_pins -to $fp_capture_pins
}

set generated_bit [file join $proj_dir bupt_riscv.runs impl_1 top.bit]
set failing_paths [get_timing_paths -max_paths 1 -slack_lesser_than 0]
if {[llength $failing_paths] > 0} {
    set worst_slack [get_property SLACK [lindex $failing_paths 0]]
    puts "BUPT_RISCV_POST_ROUTE_OPT initial_worst_slack=${worst_slack}"
    if {[catch {phys_opt_design -directive AggressiveExplore} opt_msg]} {
        puts "BUPT_RISCV_POST_ROUTE_PHYS_OPT_SKIPPED $opt_msg"
    }
    if {[catch {route_design -directive Explore} route_msg]} {
        puts "BUPT_RISCV_POST_ROUTE_ROUTE_SKIPPED $route_msg"
    }
    report_timing_summary -max_paths 10 -report_unconstrained \
        -file [file join $proj_dir post_route_opt_timing_summary.rpt] \
        -warn_on_violation
    set failing_paths [get_timing_paths -max_paths 1 -slack_lesser_than 0]
    if {[llength $failing_paths] > 0} {
        set worst_slack [get_property SLACK [lindex $failing_paths 0]]
        error "BUPT RISC-V timing failed: worst slack ${worst_slack} ns"
    }
    write_bitstream -force $generated_bit
}

file copy -force $generated_bit $bit_out
puts "BUPT_RISCV_BITSTREAM=$bit_out"
