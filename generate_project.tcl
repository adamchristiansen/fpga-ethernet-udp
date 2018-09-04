# This script is used to create the Vivado project from everything in the /src
# directory beside this script.
#
# To use this script, open Xilinx Vivado and select `Tools > Run Tcl Script...`,
# then select the `generate_project.tcl` script in the file exporer. The script
# will run and produce the Vivado project by importing all of the project
# sources.

#-------------------------------------------------------------------------------
# Parameters
#-------------------------------------------------------------------------------

# All of the main parameters that can be configured are set in this section.
# These can be changed as desired.

# The name to use for the project.
set project_name "fpga_ethernet_udp"

# The part number of the hardware.
set part_number "xc7a35ticsg324-1L"

# The language to use in simulation. This can be VHDL, Verilog, or Mixed.
set simulator_language "Mixed"

# The target language to use for synthesis. This can be VHDL or Verilog.
set target_language "Verilog"

# This is the name of the top module. This is not the name of the file that
# contains the top module, but the name of the module itself (in the code).
# This can be set to an empty string to let the tools decide the top module
# automatically.
set top_module ""

# This is the name of the top module to use in simulation. This is not the name
# of the file that contains the top module, but the name of the module itself
# (in the code). This can be set to an empty string to let the tools decide the
# top module automatically.
set top_sim_module ""

# The root path that all other paths are to be specified with. This is by
# default the path to the directory that this script is in, and it is not
# recommended that this be changed.
set origin_dir [file dirname [file normalize [info script]]]

# The directory that Tcl script files are located.
set tcl_dir "$origin_dir/tcl"

# The directory that the constraints source files are located.
set constraints_dir "$origin_dir/src/constraints"

# The directory that the HDL source files are located.
set hdl_dir "$origin_dir/src/hdl"

# The directory that is used for the individual IP files used in the project.
set ip_dir "$origin_dir/src/ip"

# The directory that is used for the IP repository.
set repo_dir "$origin_dir/src/repo"

# The directory that the simulation files are located.
set sim_dir "$origin_dir/src/sim"

# The directory that the Vivado project will be generated in. All Vivado project
# files will be stored in this directory.
set project_dir "$origin_dir/proj"

# Get the year from the Vivado version. This is used for automatically selecting
# the synthesis and implementation strategies.
set year [lindex [split [version -short] .] 0]

# The strategies and flows to use in synthesis.
set synthesis_flow "Vivado Synthesis ${year}"
set synthesis_report_strategy "Vivado Synthesis Default Reports"
set synthesis_strategy "Vivado Synthesis Defaults"

# The strategies and flows to use in implementation.
set implementation_flow "Vivado Implementation ${year}"
set implementation_report_strategy "Vivado Implementation Default Reports"
set implementation_strategy "Vivado Implementation Defaults"

# This is a list of messages whose severities should be changed. This is treated
# like a list of tuples where the first element in tuple is the message ID and
# the second is the new severity for it.
set message_severities {
    { "Power 33-332"  "INFO"     }
    { "Synth 8-3331"  "ADVISORY" }
    { "Synth 8-3332"  "INFO"     }
    { "Synth 8-5858"  "INFO"     }
    { "Synth 8-6014"  "INFO"     }
    { "Timing 38-316" "INFO"     }
}

# These are scripts that can be hooked into at certain stages of the build.
# These are entirely optional, and will only be used if they exist.
# Synthesis
set synth_design_pre  "$tcl_dir/synth_design_pre.tcl"
set synth_design_post "$tcl_dir/synth_design_post.tcl"
# Implementation
set opt_design_pre                   "$tcl_dir/opt_design_pre.tcl"
set opt_design_post                  "$tcl_dir/opt_design_post.tcl"
set phys_opt_design_pre              "$tcl_dir/phys_opt_design_pre.tcl"
set phys_opt_design_post             "$tcl_dir/phys_opt_design_post.tcl"
set place_design_pre                 "$tcl_dir/place_design_pre.tcl"
set place_design_post                "$tcl_dir/place_design_post.tcl"
set power_opt_design_pre             "$tcl_dir/power_opt_design_pre.tcl"
set power_opt_design_post            "$tcl_dir/power_opt_design_post.tcl"
set post_place_power_opt_design_pre  "$tcl_dir/post_place_power_opt_design_pre.tcl"
set post_place_power_opt_design_post "$tcl_dir/post_place_power_opt_design_post.tcl"
set post_route_phys_opt_design_pre   "$tcl_dir/post_route_phys_opt_design_pre.tcl"
set post_route_phys_opt_design_post  "$tcl_dir/post_route_phys_opt_design_post.tcl"
set route_design_pre                 "$tcl_dir/route_design_pre.tcl"
set route_design_post                "$tcl_dir/route_design_post.tcl"
set write_bitstream_pre              "$tcl_dir/write_bitstream_pre.tcl"
set write_bitstream_post             "$tcl_dir/write_bitstream_post.tcl"

#-------------------------------------------------------------------------------
# Create Project
#-------------------------------------------------------------------------------

# This part of the script creates a new project in the proj/ directory relative
# to this script.

# Create a project to add the source files to
create_project $project_name $project_dir

# Set the message severities for the project
for { set i 0 } { $i < [llength $message_severities] } { incr i } {
    set item [lindex $message_severities $i]
    set message_id [lindex $item 0]
    set new_severity [lindex $item 1]
    set_msg_config -ruleid $i -id $message_id -new_severity $new_severity
}

# Project properties
set obj [get_projects $project_name]
set_property default_lib xil_defaultlib $obj
set_property part $part_number $obj
set_property simulator_language $simulator_language $obj
set_property target_language $target_language $obj

# Create 'constrs_1' fileset if it does not exist, and add the constraints files
if { [string equal [get_filesets -quiet constrs_1] ""] } {
    create_fileset -constrset constrs_1
}
if { [file isdirectory $constraints_dir] == 1 } {
    add_files -fileset constrs_1 -quiet $constraints_dir
}

# Create 'sources_1' fileset if it does not exist, and add the source files
if { [string equal [get_filesets -quiet sources_1] ""] } {
    create_fileset -srcset sources_1
}
if { [file isdirectory $hdl_dir] == 1 } {
    add_files -fileset sources_1 -quiet $hdl_dir
}

# Set the top module for the design if it was specified
if { ! [string equal $top_module ""] } {
    set_property top $top_module [get_filesets sources_1]
}

# Import the existing IP
if { [file isdirectory $ip_dir] == 1 } {
    add_files -quiet [glob -nocomplain $ip_dir/*/*.xci]
    update_ip_catalog
}

# Create 'sim_1' fileset if it does not exist, and add the simulation files
if { [string equal [get_filesets -quiet constrs_1] ""] } {
    create_fileset -simset sim_1
}
if { [file isdirectory $sim_dir] == 1 } {
    add_files -fileset sim_1 -quiet $sim_dir
}

# Set the top module for simulation if it was specified
if { ! [string equal $top_sim_module ""] } {
    set_property top $top_sim_module [get_filesets sim_1]
}

# Set up the repository path
if { [file isdirectory $repo_dir] == 1 } {
    set obj [get_filesets sources_1]
    set_property ip_repo_paths $repo_dir $obj
}

#-------------------------------------------------------------------------------
# Synthesis
#-------------------------------------------------------------------------------

# Create 'synth_1' run if it does not exist, then set the synthesis parameters
# and mark 'synth_1' as the current synthesis run.
if { [string equal [get_runs -quiet synth_1] ""] } {
    create_run -name synth_1
}
set obj [get_runs synth_1]

set_property constrset constrs_1 $obj
set_property flow $synthesis_flow $obj
set_property part $part_number $obj
set_property report_strategy $synthesis_report_strategy $obj
set_property strategy $synthesis_strategy $obj

if { [file exists "$synth_design_pre"] } {
    set_property steps.opt_design.tcl.pre "$synth_design_pre" $obj
}
if { [file exists "$synth_design_post"] } {
    set_property steps.opt_design.tcl.post "$synth_design_post" $obj
}

current_run -synthesis $obj

#-------------------------------------------------------------------------------
# Implementation
#-------------------------------------------------------------------------------

# Create 'impl_1' run if it does not exist, then set the implementation
# parameters and mark 'impl_1' as the current implementation run.
if { [string equal [get_runs -quiet impl_1] ""] } {
    create_run -name impl_1 -parent_run synth_1
}
set obj [get_runs impl_1]

set_property constrset constrs_1 $obj
set_property flow $implementation_flow $obj
set_property part $part_number $obj
set_property report_strategy $implementation_report_strategy $obj
set_property steps.write_bitstream.args.bin_file 1 $obj
set_property strategy $implementation_strategy $obj

if { [file exists "$opt_design_pre"] } {
    set_property steps.opt_design.tcl.pre "$opt_design_pre" $obj
}
if { [file exists "$opt_design_post"] } {
    set_property steps.opt_design.tcl.post "$opt_design_post" $obj
}
if { [file exists "$phys_opt_design_pre"] } {
    set_property steps.phys_opt_design.tcl.pre "$phys_opt_design_pre" $obj
}
if { [file exists "$phys_opt_design_post"] } {
    set_property steps.phys_opt_design.tcl.post "$phys_opt_design_post" $obj
}
if { [file exists "$place_design_pre"] } {
    set_property steps.place_design.tcl.pre "$place_design_pre" $obj
}
if { [file exists "$place_design_post"] } {
    set_property steps.place_design.tcl.post "$place_design_post" $obj
}
if { [file exists "$power_opt_design_pre"] } {
    set_property steps.power_opt_design.tcl.pre "$power_opt_design_pre" $obj
}
if { [file exists "$power_opt_design_post"] } {
    set_property steps.power_opt_design.tcl.post "$power_opt_design_post" $obj
}
if { [file exists "$post_place_power_opt_design_pre"] } {
    set_property steps.post_place_power_opt_design.tcl.pre "$post_place_power_opt_design_pre" $obj
}
if { [file exists "$post_place_power_opt_design_post"] } {
    set_property steps.post_place_power_opt_design.tcl.post "$post_place_power_opt_design_post" $obj
}
if { [file exists "$post_route_phys_opt_design_pre"] } {
    set_property steps.post_route_phys_opt_design.tcl.pre "$post_route_phys_opt_design_pre" $obj
}
if { [file exists "$post_route_phys_opt_design_post"] } {
    set_property steps.post_route_phys_opt_design.tcl.post "$post_route_phys_opt_design_post" $obj
}
if { [file exists "$route_design_pre"] } {
    set_property steps.route_design.tcl.pre "$route_design_pre" $obj
}
if { [file exists "$route_design_post"] } {
    set_property steps.route_design.tcl.post "$route_design_post" $obj
}
if { [file exists "$write_bitstream_pre"] } {
    set_property steps.write_bitstream.tcl.pre "$write_bitstream_pre" $obj
}
if { [file exists "$write_bitstream_post"] } {
    set_property steps.write_bitstream.tcl.post "$write_bitstream_post" $obj
}

current_run -implementation $obj

#-------------------------------------------------------------------------------
# Implementation Reports
#-------------------------------------------------------------------------------

# Create 'impl_1_init_report_timing_summary_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_init_report_timing_summary_0] ""] } {
    create_report_config -report_name impl_1_init_report_timing_summary_0 -report_type report_timing_summary:1.0 -steps init_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_init_report_timing_summary_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    set_property is_enabled 0 $obj
}

# Create 'impl_1_opt_report_drc_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_opt_report_drc_0] ""] } {
    create_report_config -report_name impl_1_opt_report_drc_0 -report_type report_drc:1.0 -steps opt_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_opt_report_drc_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_opt_report_timing_summary_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_opt_report_timing_summary_0] ""] } {
    create_report_config -report_name impl_1_opt_report_timing_summary_0 -report_type report_timing_summary:1.0 -steps opt_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_opt_report_timing_summary_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    set_property is_enabled 0 $obj
}

# Create 'impl_1_power_opt_report_timing_summary_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_power_opt_report_timing_summary_0] ""] } {
  create_report_config -report_name impl_1_power_opt_report_timing_summary_0 -report_type report_timing_summary:1.0 -steps power_opt_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_power_opt_report_timing_summary_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    set_property is_enabled 0 $obj
}

# Create 'impl_1_place_report_io_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_io_0] ""] } {
    create_report_config -report_name impl_1_place_report_io_0 -report_type report_io:1.0 -steps place_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_io_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_place_report_utilization_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_utilization_0] ""] } {
    create_report_config -report_name impl_1_place_report_utilization_0 -report_type report_utilization:1.0 -steps place_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_utilization_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_place_report_control_sets_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_control_sets_0] ""] } {
    create_report_config -report_name impl_1_place_report_control_sets_0 -report_type report_control_sets:1.0 -steps place_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_control_sets_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_place_report_incremental_reuse_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_incremental_reuse_0] ""] } {
    create_report_config -report_name impl_1_place_report_incremental_reuse_0 -report_type report_incremental_reuse:1.0 -steps place_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_incremental_reuse_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    set_property is_enabled 0 $obj
}

# Create 'impl_1_place_report_incremental_reuse_1' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_incremental_reuse_1] ""] } {
  create_report_config -report_name impl_1_place_report_incremental_reuse_1 -report_type report_incremental_reuse:1.0 -steps place_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_incremental_reuse_1]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    set_property is_enabled 0 $obj
}

# Create 'impl_1_place_report_timing_summary_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_timing_summary_0] ""] } {
    create_report_config -report_name impl_1_place_report_timing_summary_0 -report_type report_timing_summary:1.0 -steps place_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_place_report_timing_summary_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    set_property is_enabled 0 $obj
}

# Create 'impl_1_post_place_power_opt_report_timing_summary_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_post_place_power_opt_report_timing_summary_0] ""] } {
    create_report_config -report_name impl_1_post_place_power_opt_report_timing_summary_0 -report_type report_timing_summary:1.0 -steps post_place_power_opt_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_post_place_power_opt_report_timing_summary_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    set_property is_enabled 0 $obj
}

# Create 'impl_1_phys_opt_report_timing_summary_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_phys_opt_report_timing_summary_0] ""] } {
    create_report_config -report_name impl_1_phys_opt_report_timing_summary_0 -report_type report_timing_summary:1.0 -steps phys_opt_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_phys_opt_report_timing_summary_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    set_property is_enabled 0 $obj
}

# Create 'impl_1_route_report_drc_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_drc_0] ""] } {
    create_report_config -report_name impl_1_route_report_drc_0 -report_type report_drc:1.0 -steps route_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_drc_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_route_report_methodology_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_methodology_0] ""] } {
    create_report_config -report_name impl_1_route_report_methodology_0 -report_type report_methodology:1.0 -steps route_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_methodology_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_route_report_power_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_power_0] ""] } {
    create_report_config -report_name impl_1_route_report_power_0 -report_type report_power:1.0 -steps route_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_power_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_route_report_route_status_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_route_status_0] ""] } {
    create_report_config -report_name impl_1_route_report_route_status_0 -report_type report_route_status:1.0 -steps route_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_route_status_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_route_report_timing_summary_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_timing_summary_0] ""] } {
    create_report_config -report_name impl_1_route_report_timing_summary_0 -report_type report_timing_summary:1.0 -steps route_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_timing_summary_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_route_report_incremental_reuse_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_incremental_reuse_0] ""] } {
    create_report_config -report_name impl_1_route_report_incremental_reuse_0 -report_type report_incremental_reuse:1.0 -steps route_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_incremental_reuse_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_route_report_clock_utilization_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_clock_utilization_0] ""] } {
    create_report_config -report_name impl_1_route_report_clock_utilization_0 -report_type report_clock_utilization:1.0 -steps route_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_clock_utilization_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_route_report_bus_skew_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_bus_skew_0] ""] } {
    create_report_config -report_name impl_1_route_report_bus_skew_0 -report_type report_bus_skew:1.1 -steps route_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_route_report_bus_skew_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_post_route_phys_opt_report_timing_summary_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_post_route_phys_opt_report_timing_summary_0] ""] } {
  create_report_config -report_name impl_1_post_route_phys_opt_report_timing_summary_0 -report_type report_timing_summary:1.0 -steps post_route_phys_opt_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_post_route_phys_opt_report_timing_summary_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}

# Create 'impl_1_post_route_phys_opt_report_bus_skew_0' report (if not found)
if { [string equal [get_report_configs -of_objects [get_runs impl_1] impl_1_post_route_phys_opt_report_bus_skew_0] ""] } {
    create_report_config -report_name impl_1_post_route_phys_opt_report_bus_skew_0 -report_type report_bus_skew:1.1 -steps post_route_phys_opt_design -runs impl_1
}
set obj [get_report_configs -of_objects [get_runs impl_1] impl_1_post_route_phys_opt_report_bus_skew_0]
if { $obj != "" } {
    # Uncomment the following line to disable the report
    #set_property is_enabled 0 $obj
}
