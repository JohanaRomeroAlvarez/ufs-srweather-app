#!/usr/bin/env bash


#
#-----------------------------------------------------------------------
#
# This script generates NetCDF-formatted grid files required as input
# the FV3 model configured for the regional domain.
#
# The output of this script is placed in a directory defined by GRID_DIR.
#
# More about the grid for regional configurations of FV3:
#
#    a) This script creates grid files for tile 7 (reserved for the
#       regional grid located soewhere within tile 6 of the 6 global
#       tiles.
#
#    b) Regional configurations of FV3 need two grid files, one with 3
#       halo cells and one with 4 halo cells. The width of the halo is
#       the number of cells in the direction perpendicular to the
#       boundary.
#
#    c) The tile 7 grid file that this script creates includes a halo,
#       with at least 4 cells to accommodate this requirement. The halo
#       is made thinner in a subsequent step called "shave".
#
#    d) We will let NHW denote the width of the wide halo that is wider
#       than the required 3- or 4-cell halos. (NHW; N=number of cells,
#       H=halo, W=wide halo)
#
#    e) T7 indicates the cell count on tile 7.
#
#
# This script does the following:
#
#   - Create the grid, either an ESGgrid with the regional_esg_grid
#     executable or a GFDL-type grid with the hgrid executable
#   - Calculate the regional grid's global uniform cubed-sphere grid
#     equivalent resolution with the global_equiv_resol executable
#   - Use the shave executable to reduce the halo to 3 and 4 cells
#   - Call an ush script that runs the make_solo_mosaic executable
#
# Run-time environment variables:
#
#    DATA
#    GLOBAL_VAR_DEFNS_FP
#    REDIRECT_OUT_ERR
#
# Experiment variables
#
#  user:
#    EXECdir
#    USHdir
#
#  platform:
#    PRE_TASK_CMDS
#    RUN_CMD_SERIAL

#  workflow:
#    DOT_OR_USCORE
#    GRID_GEN_METHOD
#    RES_IN_FIXLAM_FILENAMES
#    RGNL_GRID_NML_FN
#    VERBOSE
#
#  task_make_grid:
#    GFDLgrid_NUM_CELLS
#    GFDLgrid_USE_NUM_CELLS_IN_FILENAMES
#    GRID_DIR
#
#  constants:
#    NH3
#    NH4
#    TILE_RGNL
#
#  grid_params:
#    DEL_ANGLE_X_SG
#    DEL_ANGLE_Y_SG
#    GFDLgrid_REFINE_RATIO
#    IEND_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG
#    ISTART_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG
#    JEND_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG
#    JSTART_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG
#    LAT_CTR
#    LON_CTR
#    NEG_NX_OF_DOM_WITH_WIDE_HALO
#    NEG_NY_OF_DOM_WITH_WIDE_HALO
#    NHW
#    NX
#    NY
#    PAZI
#    STRETCH_FAC
#
#-----------------------------------------------------------------------
#

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. ${USHsrw}/source_util_funcs.sh
for sect in user nco platform workflow constants grid_params task_make_grid ; do
  source_yaml ${GLOBAL_VAR_DEFNS_FP} ${sect}
done
#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; set -xue; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located 
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( $READLINK -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )
#
#-----------------------------------------------------------------------
#
# Print message indicating entry into script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that generates grid files.
========================================================================"
#
#-----------------------------------------------------------------------
#
# Set the machine-dependent run command.  Also, set resource limits as
# necessary.
#
#-----------------------------------------------------------------------
#
eval ${PRE_TASK_CMDS}

if [ -z "${RUN_CMD_SERIAL:-}" ] ; then
  print_err_msg_exit " \
  Run command was not set in machine file. \
  Please set RUN_CMD_SERIAL for your platform"
else
  print_info_msg "$VERBOSE" "
  All executables will be submitted with command \'${RUN_CMD_SERIAL}\'."
fi

#
#-----------------------------------------------------------------------
#
# Generate grid files.
#
# The following will create 7 grid files (one per tile, where the 7th
# "tile" is the grid that covers the regional domain) named
#
#   ${CRES}_grid.tileN.nc for N=1,...,7.
#
# It will also create a mosaic file named ${CRES}_mosaic.nc that con-
# tains information only about tile 7 (i.e. it does not have any infor-
# mation on how tiles 1 through 6 are connected or that tile 7 is within
# tile 6).  All these files will be placed in the directory specified by
# GRID_DIR.  Note that the file for tile 7 will include a halo of width
# NHW cells.
#
# Since tiles 1 through 6 are not needed to run the FV3-LAM model and are
# not used later on in any other preprocessing steps, it is not clear
# why they are generated.  It might be because it is not possible to di-
# rectly generate a standalone regional grid using the make_hgrid uti-
# lity/executable that grid_gen_scr calls, i.e. it might be because with
# make_hgrid, one has to either create just the 6 global tiles or create
# the 6 global tiles plus the regional (tile 7), and then for the case
# of a regional simulation (i.e. GTYPE="regional", which is always the
# case here) just not use the 6 global tiles.
#
# The grid_gen_scr script called below takes its next-to-last argument
# and passes it as an argument to the --halo flag of the make_hgrid uti-
# lity/executable.  make_hgrid then checks that a regional (or nested)
# grid of size specified by the arguments to its --istart_nest, --iend_-
# nest, --jstart_nest, and --jend_nest flags with a halo around it of
# size specified by the argument to the --halo flag does not extend be-
# yond the boundaries of the parent grid (tile 6).  In this case, since
# the values passed to the --istart_nest, ..., and --jend_nest flags al-
# ready include a halo (because these arguments are
#
#   ${ISTART_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG},
#   ${IEND_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG},
#   ${JSTART_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG}, and
#   ${JEND_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG},
#
# i.e. they include "WITH_WIDE_HALO_" in their names), it is reasonable
# to pass as the argument to --halo a zero.  However, make_hgrid re-
# quires that the argument to --halo be at least 1, so below, we pass a
# 1 as the next-to-last argument to grid_gen_scr.
#
# More information on make_hgrid:
# ------------------------------
#
# The grid_gen_scr called below in turn calls the make_hgrid executable
# as follows:
#
#   make_hgrid \
#   --grid_type gnomonic_ed \
#   --nlon 2*${RES} \
#   --grid_name C${RES}_grid \
#   --do_schmidt --stretch_factor ${STRETCH_FAC} \
#   --target_lon ${LON_CTR}
#   --target_lat ${LAT_CTR} \
#   --nest_grid --parent_tile 6 --refine_ratio ${GFDLgrid_REFINE_RATIO} \
#   --istart_nest ${ISTART_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG} \
#   --jstart_nest ${JSTART_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG} \
#   --iend_nest ${IEND_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG} \
#   --jend_nest ${JEND_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG} \
#   --halo ${NH3} \
#   --great_circle_algorithm
#
# This creates the 7 grid files ${CRES}_grid.tileN.nc for N=1,...,7.
# The 7th file ${CRES}_grid.tile7.nc represents the regional grid, and
# the extents of the arrays in that file do not seem to include a halo,
# i.e. they are based only on the values passed via the four flags
#
#   --istart_nest ${ISTART_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG}
#   --jstart_nest ${JSTART_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG}
#   --iend_nest ${IEND_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG}
#   --jend_nest ${JEND_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG}
#
# According to Rusty Benson of GFDL, the flag
#
#   --halo ${NH3}
#
# only checks to make sure that the nested or regional grid combined
# with the specified halo lies completely within the parent tile.  If
# so, make_hgrid issues a warning and exits.  Thus, the --halo flag is
# not meant to be used to add a halo region to the nested or regional
# grid whose limits are specified by the flags --istart_nest, --iend_-
# nest, --jstart_nest, and --jend_nest.
#
# Note also that make_hgrid has an --out_halo option that, according to
# the documentation, is meant to output extra halo cells around the
# nested or regional grid boundary in the file generated by make_hgrid.
# However, according to Rusty Benson of GFDL, this flag was originally
# created for a special purpose and is limited to only outputting at
# most 1 extra halo point.  Thus, it should not be used.
#
#-----------------------------------------------------------------------
#

#
#-----------------------------------------------------------------------
#
# Generate grid file.
#
#-----------------------------------------------------------------------
#
print_info_msg "$VERBOSE" "Starting grid file generation..."
#
# Generate a GFDLgrid-type of grid.
#
if [ "${GRID_GEN_METHOD}" = "GFDLgrid" ]; then
  #
  # Set local variables needed in the call to the executable that generates
  # a GFDLgrid-type grid.
  #
  nx_t6sg=$(( 2*GFDLgrid_NUM_CELLS ))
  grid_name="${GRID_GEN_METHOD}"
  #
  # Call the executable that generates the grid file.  Note that this call
  # will generate a file not only the regional grid (tile 7) but also files
  # for the 6 global tiles.  However, after this call we will only need the
  # regional grid file.
  #
  export pgm="make_hgrid"
  . prep_step

  eval $RUN_CMD_SERIAL ${exec_fp} \
    --grid_type gnomonic_ed \
    --nlon ${nx_t6sg} \
    --grid_name ${grid_name} \
    --do_schmidt \
    --stretch_factor ${STRETCH_FAC} \
    --target_lon ${LON_CTR} \
    --target_lat ${LAT_CTR} \
    --nest_grid \
    --parent_tile 6 \
    --refine_ratio ${GFDLgrid_REFINE_RATIO} \
    --istart_nest ${ISTART_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG} \
    --jstart_nest ${JSTART_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG} \
    --iend_nest ${IEND_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG} \
    --jend_nest ${JEND_OF_RGNL_DOM_WITH_WIDE_HALO_ON_T6SG} \
    --halo 1 \
    --great_circle_algorithm >>$pgmout 2>${tmpdir}/errfile
  export err=$?; err_chk
  mv errfile errfile_make_hgrid
  #
  # Set the name of the regional grid file generated by the above call.
  #
  grid_fn="${grid_name}.tile${TILE_RGNL}.nc"

#
# Generate a ESGgrid-type of grid.
#
elif [ "${GRID_GEN_METHOD}" = "ESGgrid" ]; then
  #
  # Create the namelist file read in by the ESGgrid-type grid generation
  # code in the temporary subdirectory.
  #
  rgnl_grid_nml_fp="$DATA/${RGNL_GRID_NML_FN}"
  #
  # Create a multiline variable that consists of a yaml-compliant string
  # specifying the values that the namelist variables need to be set to
  # (one namelist variable per line, plus a header and footer).  Below,
  # this variable will be passed to a python script that will create the
  # namelist file.
  #
  settings="
'regional_grid_nml':
  'plon': ${LON_CTR}
  'plat': ${LAT_CTR}
  'delx': ${DEL_ANGLE_X_SG}
  'dely': ${DEL_ANGLE_Y_SG}
  'lx': ${NEG_NX_OF_DOM_WITH_WIDE_HALO}
  'ly': ${NEG_NY_OF_DOM_WITH_WIDE_HALO}
  'pazi': ${PAZI}
"

  # UW takes input from stdin when no -i/--input-config flag is provided
  (cat << EOF
$settings
EOF
) | uw config realize \
    --input-format yaml \
    -o ${rgnl_grid_nml_fp} \
    -v \

  err=$?
  if [ $err -ne 0 ]; then
      print_err_msg_exit "\
  Error creating regional_esg_grid namelist.
      Settings for input are:
  $settings"
  fi
  #
  # Call the executable that generates the grid file.
  #
  export pgm="regional_esg_grid"
  . prep_step

  eval $RUN_CMD_SERIAL ${exec_fp} ${rgnl_grid_nml_fp} >>$pgmout 2>errfile
  export err=$?; err_chk
  mv errfile errfile_regional_esg_grid
  #
  # Set the name of the regional grid file generated by the above call.
  # This must be the same name as in the regional_esg_grid code.
  #
  grid_fn="regional_grid.nc"
fi
#
# Set the full path to the grid file generated above.  Then change location
# to the original directory.
#
grid_fp="$DATA/${grid_fn}"

print_info_msg "$VERBOSE" "Grid file generation completed successfully."
#
#-----------------------------------------------------------------------
#
# Calculate the regional grid's global uniform cubed-sphere grid equivalent
# resolution.
#
#-----------------------------------------------------------------------
#
export pgm="global_equiv_resol"
. prep_step

eval $RUN_CMD_SERIAL ${exec_fp} "${grid_fp}" >>$pgmout 2>errfile
export err=$?; err_chk
mv errfile errfile_global_equiv_resol

# Make sure 'ncdump' is available before we try to use it
if ! command -v ncdump &> /dev/null
then
  print_err_msg_exit "\
The utility 'ncdump' was not found in the environment. Be sure to add the
netCDF 'bin/' directory to your PATH."
fi

# Make the following (reading of res_equiv) a function in another file
# so that it can be used both here and in the exregional_make_orog.sh
# script.
res_equiv=$( ncdump -h "${grid_fp}" | \
             grep -o ":RES_equiv = [0-9]\+" | grep -o "[0-9]" ) || \
print_err_msg_exit "\
Attempt to extract the equivalent global uniform cubed-sphere grid reso-
lution from the grid file (grid_fp) failed:
  grid_fp = \"${grid_fp}\""
res_equiv=${res_equiv//$'\n'/}
#
#-----------------------------------------------------------------------
#
# Set the string CRES that will be comprise the start of the grid file
# name (and other file names later in other tasks/scripts).  Then set its
# value in the variable definitions file.
#
#-----------------------------------------------------------------------
#
if [ "${GRID_GEN_METHOD}" = "GFDLgrid" ]; then
  if [ $(boolify "${GFDLgrid_USE_NUM_CELLS_IN_FILENAMES}") = "TRUE" ]; then
    CRES="C${GFDLgrid_NUM_CELLS}"
  else
    CRES="C${res_equiv}"
  fi
elif [ "${GRID_GEN_METHOD}" = "ESGgrid" ]; then
  CRES="C${res_equiv}"
fi

# UW takes the update values from stdin when no --update-file flag is
# provided. It needs --update-format to do it correctly, though.
echo "workflow: {CRES: ${CRES}}" | uw config realize \
  --input-file $GLOBAL_VAR_DEFNS_FP \
  --update-format yaml \
  --output-file $GLOBAL_VAR_DEFNS_FP \
  --verbose

#
#-----------------------------------------------------------------------
#
# Move the grid file from the temporary directory to GRID_DIR.  In the
# process, rename it such that its name includes CRES and the halo width.
#
#-----------------------------------------------------------------------
#
grid_fp_orig="${grid_fp}"
grid_fn="${CRES}${DOT_OR_USCORE}grid.tile${TILE_RGNL}.halo${NHW}.nc"
grid_fp="${GRID_DIR}/${grid_fn}"
mv "${grid_fp_orig}" "${grid_fp}"
#
#-----------------------------------------------------------------------
#
# If there are pre-existing orography or climatology files that we will
# be using (i.e. if task_make_grid or task_make_sfc_climo ran in the
# experiment, RES_IN_FIXLAM_FILENAMES will not be set to a null string),
# check that the grid resolution contained in the variable CRES set
# above matches the resolution appearing in the names of the preexisting
# orography and/or surface climatology files.
#
#-----------------------------------------------------------------------
#
if [ ! -z "${RES_IN_FIXLAM_FILENAMES}" ]; then
  res="${CRES:1}"
  if [ "$res" -ne "${RES_IN_FIXLAM_FILENAMES}" ]; then
    print_err_msg_exit "\
The resolution (res) calculated for the grid does not match the resolution
(RES_IN_FIXLAM_FILENAMES) appearing in the names of the orography and/or
surface climatology files:
  res = \"$res\"
  RES_IN_FIXLAM_FILENAMES = \"${RES_IN_FIXLAM_FILENAMES}\""
  fi
fi
#
#-----------------------------------------------------------------------
#
# Partially "shave" the halo from the grid file having a wide halo to
# generate two new grid files -- one with a 3-grid-wide halo and another
# with a 4-cell-wide halo.  These are needed as inputs by the forecast
# model as well as by the code (chgres_cube) that generates the lateral
# boundary condition files.
#
#-----------------------------------------------------------------------
#
# Set the full path to the "unshaved" grid file, i.e. the one with a wide
# halo.  This is the input grid file for generating both the grid file
# with a 3-cell-wide halo and the one with a 4-cell-wide halo.
#
unshaved_fp="${grid_fp}"

export pgm="shave"

halo_num_list=('0' '3' '4')
for halo_num in "${halo_num_list[@]}"; do
  print_info_msg "Shaving grid file with ${halo_num}-cell-wide halo..."

  nml_fn="input.shave.grid.halo${halo_num}"
  shaved_fp="${tmpdir}/${CRES}${DOT_OR_USCORE}grid.tile${TILE_RGNL}.halo${halo_num}.nc"
  printf "%s %s %s %s %s\n" \
  $NX $NY ${halo_num} \"${unshaved_fp}\" \"${shaved_fp}\" \
  > ${nml_fn}

  . prep_step

  eval $RUN_CMD_SERIAL ${EXECdir}/$pgm < ${nml_fn} >>$pgmout 2>errfile
  export err=$?; err_chk
  mv errfile errfile_shave_nh${halo_num}
  mv ${shaved_fp} ${GRID_DIR}
done
#
#-----------------------------------------------------------------------
#
# Create the grid mosaic files with various cell-wide halos.
#
#-----------------------------------------------------------------------
#
export pgm="make_solo_mosaic"

halo_num_list[${#halo_num_list[@]}]="${NHW}"
for halo_num in "${halo_num_list[@]}"; do
  print_info_msg "Creating grid mosaic file with ${halo_num}-cell-wide halo..."  
  grid_fn="${CRES}${DOT_OR_USCORE}grid.tile${TILE_RGNL}.halo${halo_num}.nc"
  grid_fp="${GRID_DIR}/${grid_fn}"
  mosaic_fn="${CRES}${DOT_OR_USCORE}mosaic.halo${halo_num}.nc"
  mosaic_fp="${GRID_DIR}/${mosaic_fn}"
  mosaic_fp_prefix="${mosaic_fp%.*}"

  . prep_step

  eval ${RUN_CMD_SERIAL} ${EXECdir}/$pgm \
      --num_tiles 1 \
      --dir "${GRID_DIR}" \
      --tile_file "${grid_fn}" \
      --mosaic "${mosaic_fp_prefix}" >>$pgmout 2>errfile
  export err=$?; err_chk
  mv errfile errfile_mosaic_nh${halo_num}  
done
#
#-----------------------------------------------------------------------
#
# Create symlinks in the FIXlam directory to the grid and mosaic files
# generated above in the GRID_DIR directory.
#
#-----------------------------------------------------------------------
#
${USHsrw}/link_fix.py \
  --path-to-defns ${GLOBAL_VAR_DEFNS_FP} \
  --file-group "grid" || \
print_err_msg_exit "\
Call to function to create symlinks to the various grid and mosaic files
failed."
#
#-----------------------------------------------------------------------
#
# Call a function (set_fv3nml_sfc_climo_filenames) to set the values of
# those variables in the forecast model's namelist file that specify the
# paths to the surface climatology files.  These files will either already
# be avaialable in a user-specified directory (SFC_CLIMO_DIR) or will be
# generated by the TN_MAKE_SFC_CLIMO task.  They (or symlinks to them)
# will be placed (or wll already exist) in the FIXlam directory.
#
#-----------------------------------------------------------------------
#
${USHsrw}/set_fv3nml_sfc_climo_filenames.py \
  --path-to-defns ${GLOBAL_VAR_DEFNS_FP} \
    || print_err_msg_exit "\
Call to function to set surface climatology file names in the FV3 namelist
file failed."
#
#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Grid files with various halo widths generated successfully!!!

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/func-
# tion.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1
