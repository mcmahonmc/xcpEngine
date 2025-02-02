#!/usr/bin/env bash

###################################################################
#  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  #
###################################################################

###################################################################
# SPECIFIC MODULE HEADER
# This module produce basil cbf
###################################################################
mod_name_short=basil
mod_name='BASIL CBF'
mod_head=${XCPEDIR}/core/CONSOLE_MODULE_RC

###################################################################
# GENERAL MODULE HEADER
###################################################################
source ${XCPEDIR}/core/constants
source ${XCPEDIR}/core/functions/library.sh
source ${XCPEDIR}/core/parseArgsMod

###################################################################
# MODULE COMPLETIO
###################################################################
completion() {
   source ${XCPEDIR}/core/auditComplete
   source ${XCPEDIR}/core/updateQuality
   source ${XCPEDIR}/core/moduleEnd
}

###################################################################
# OUTPUTS
###################################################################

derivative            cbfbasil            ${prefix}_cbf_basil.nii.gz
derivative            cbfbasilspatial     ${prefix}_cbf_basil_spatial.nii.gz
derivative            cbfbasilpv          ${prefix}_cbf_basil_pv.nii.gz


output           logfile              ${prefix}_logfile
output           basil_option         ${prefix}_basil_option.txt
output           logfile2             ${prefix}_logfile_spatial

output           cbfbasil            ${prefix}_cbf_basil.nii.gz
output           cbfbasilspatial     ${prefix}_cbf_basil_spatial.nii.gz
output           cbfbasilpv          ${prefix}_cbf_basil_pv.nii.gz





derivative_set       cbfbasil            Statistic         mean
derivative_set       cbfbasilspatial     Statistic         mean
derivative_set       cbfbasilpv          Statistic         mean



qc negative_voxels_basil    negativeVoxels_basil   ${prefix}_negativeVoxels.txt


<<DICTIONARY


DICTIONARY

## generate m0
subroutine @1.0 Generate m0

if ! is_image ${m0[sub]} 
   then 
   m0=${out}/basil/${prefix}_m0.nii.gz
   basil_m0_scale[cxt]=1
   if (( ${basil_inputformat[cxt]} == tc ))
   then
      exec_afni 3dcalc -prefix ${m0}  -a ${intermediate}.nii.gz'[0..$(2)]' -expr "a" 2>/dev/null   
      else
      exec_afni 3dcalc -prefix ${m0}  -a ${intermediate}.nii.gz'[1..$(2)]' -expr "a" 2>/dev/null 
   fi
   exec_fsl fslmaths ${m0} -Tmean ${m0}
   output m0  ${out}/basil/${prefix}_m0.nii.gz
else
   m0=${out}/basil/${prefix}_m0.nii.gz
   exec_fsl fslmaths ${m0[sub]} -Tmean ${m0}
   output m0  ${out}/basil/${prefix}_m0.nii.gz
fi

subroutine @1.2 register the asl and m0 to struct space
gm_seq=${out}/basil/${prefix}_gm2seq.nii.gz 
wm_seq=${out}/basil/${prefix}_wm2seq.nii.gz 
mask1=${intermediate}_mask_seq.nii.gz 
mask_asl=${out}/basil/${prefix}_mask_asl.nii.gz 
struct_asl=${out}/basil/${prefix}_struct_seq.nii.gz 

if is_image ${struct[sub]}
  then
   exec_ants antsApplyTransforms -e 3 -d 3 -r ${referenceVolume[sub]} \
        -i ${gm[sub]} -t ${struct2seq[sub]} \
        -o ${gm_seq} -n NearestNeighbor
   exec_ants antsApplyTransforms -e 3 -d 3 -r ${referenceVolume[sub]} \
        -i ${wm[sub]} -t ${struct2seq[sub]} \
        -o ${wm_seq} -n NearestNeighbor
    
  
   exec_ants antsApplyTransforms -e 3 -d 3 -r ${referenceVolume[sub]} \
        -i ${structmask[sub]} -t ${struct2seq[sub]} \
        -o ${mask1} -n NearestNeighbor  
   exec_fsl  fslmaths ${referenceVolume[sub]} -mul ${mask1} \
         -bin ${mask_asl} 
  output mask ${out}/basil/${prefix}_mask_asl.nii.gz 

  exec_ants antsApplyTransforms -e 3 -d 3 -r ${referenceVolume[sub]} \
        -i ${struct[sub]} -t ${struct2seq[sub]} \
        -o ${struct_asl} -n NearestNeighbor 
  exec_fsl fslmaths ${referenceVolume[sub]} -mul \
      ${out}/basil/${prefix}_mask_asl.nii.gz ${out}/basil/${prefix}_referenceVolumeBrain.nii.gz
  output referenceVolumeBrain ${out}/basil/${prefix}_referenceVolumeBrain.nii.gz
fi


###################################################################
# Compute cerebral blood flow with basil.
###################################################################
   


   case ${basil_perfusion[cxt]} in
   
   casl)
      subroutine              @1.1a PCASL/CASL -- Pseudocontinuous ASL
      subroutine              @1.1b Input: ${preprocessed[sub]}
      subroutine              @1.1c M0: ${m0[cxt]}
      subroutine              @1.1d mask: ${mask_asl}
      subroutine              @1.1e M0 scale: ${basil_m0_scale[cxt]}
      subroutine              @1.1f Partition coefficient: ${basil_lambda[cxt]}
      subroutine              @1.1g Post-labelling delay: ${basil_pld[cxt]}
      subroutine              @1.1i Blood T1: ${basil_t1blood[cxt]}
      subroutine              @1.1j Labelling efficiency: ${basil_alpha[cxt]}
      subroutine              @1.1k Template: ${template}
      subroutine              @1.1n pvgm  : ${gm_seq}
      subroutine              @1.1o pvwm  : ${wm_seq}
      

      if [  ${basil_pvc[cxt]} == 1 ]; then
          
          routine @2.1  compute CBF
           exec_xcp perf_asl -i ${preprocessed[sub]}      \
               -m ${mask_asl}                 \
               -o ${out}/basil                 \
               --struct=${struct_asl}   \
               --casl                          \
               --M0=${m0[cxt]}                 \
               --cgain=${basil_m0_scale[cxt]}  \
               --alpha=${basil_alpha[cxt]}     \
               --iaf=${basil_inputformat[cxt]} \
               --tis=${basil_tis[cxt]}         \
               --spatial                       \
               --tr=${basil_MOTR[cxt]}         \
               --pvgm=${gm_seq}               \
               --pvwm=${wm_seq}               \
               --pvcorr 

        elif [ ${basil_pvc[cxt]} == 0 ]; then 

          routine @2.1  compute CBF
         exec_xcp perf_asl -i ${preprocessed[sub]}      \
               -m ${mask_asl}                 \
               -o ${out}/basil                 \
               --struct=${struct_asl}   \
               --M0=${m0[sub]}                 \
               --cgain=${basil_m0_scale[cxt]}  \
               --alpha=${basil_alpha[cxt]}     \
               --iaf=${basil_inputformat[cxt]} \
               --tis=${basil_tis[cxt]}         \
               --spatial                       \
               --tr=${basil_MOTR[cxt]}         \
               --casl   
      fi
      ;;
      
   pasl)
      subroutine              @1.1a PASL
      subroutine              @1.1b Input: ${rawcbf}
      subroutine              @1.1c M0: ${M0[cxt]}
      subroutine              @1.1d mask: ${MASK[cxt]}
      subroutine              @1.1e M0 scale: ${basil_m0_scale[cxt]}
      subroutine              @1.1f Partition coefficient: ${basil_lambda[cxt]}
      subroutine              @1.1g Post-labelling delay: ${basil_pld[cxt]}
      subroutine              @1.1i Blood T1: ${basil_t1blood[cxt]}
      subroutine              @1.1j Labelling efficiency: ${basil_alpha[cxt]}
      subroutine              @1.1k Template: ${template}
      subroutine              @1.1n pvgm  : ${gm[sub]}
      subroutine              @1.1o pvwm  : ${wm[sub]}
      

      if [  ${basil_pvc[cxt]} == 1 ]; then
          
          routine @2.1  compute CBF
           exec_xcp perf_asl -i ${rawcbf}      \
               -m ${MASK[cxt]}                 \
               -o ${out}/basil                 \
               --struct=${struct_brain[cxt]}   \
               --M0=${M0[cxt]}                 \
               --cgain=${basil_m0_scale[cxt]}  \
               --alpha=${basil_alpha[cxt]}     \
               --iaf=${basil_inputformat[cxt]} \
               --tis=${basil_tis[cxt]}         \
               --spatial                       \
               --tr=${basil_MOTR[cxt]}         \
               --pvgm=${gm[sub]}               \
               --pvwm=${wm[sub]}               \
               --pvcorr 

        elif [ ${basil_pvc[cxt]} == 0 ]; then 

          routine @2.1  compute CBF
         exec_xcp perf_asl -i ${rawcbf}       \
               -m ${MASK[cxt]}                 \
               -o ${out}/basil                 \
               --struct=${struct_brain[cxt]}   \
               --M0=${M0[cxt]}                 \
               --cgain=${basil_m0_scale[cxt]}  \
               --alpha=${basil_alpha[cxt]}     \
               --iaf=${basil_inputformat[cxt]} \
               --tis=${basil_tis[cxt]}         \
               --spatial                       \
               --tr=${basil_MOTR[cxt]}         
      fi
      ;;
     
   esac

###################################################################
# organize the ouput
###################################################################
routine @3 Orgainizing the output 

  if [ ${basil_pvc[cxt]} == 1 ]; then 
    
    exec_fsl immv  $out/basil/cbf_calib   $out/basil/${prefix}_cbf_basil
    exec_fsl immv  $out/basil/cbf   $out/basil/${prefix}_cbf
    exec_fsl immv  $out/basil/cbf_pv_gm_calib   $out/basil/${prefix}_cbf_basil_pv
    exec_fsl immv  $out/basil/cbf_pv_wm_calib   $out/basil/${prefix}_cbf_pv_wm_calib
    exec_fsl immv  $out/basil/cbf_pv   $out/basil/${prefix}_cbf_pv
    exec_fsl immv  $out/basil/cbf_pv_gm   $out/basil/${prefix}_cbf_pv_gm
    exec_fsl immv  $out/basil/cbf_pv_wm   $out/basil/${prefix}_cbf_pv_wm
    exec_fsl immv  $out/basil/cbf_spatial_calib   $out/basil/${prefix}_cbf_basil_spatial
    exec_fsl immv  $out/basil/cbf_spatial  $out/basil/${prefix}_cbf_spatial
    exec_fsl immv  $out/basil/M0   $out/basil/${prefix}_M0
    exec_fsl immv  $out/basil/mask   $out/basil/${prefix}_mask
    exec_sys mv    $out/basil/basil_option.txt  $out/basil/${prefix}_basil_option.txt
    exec_sys mv    $out/basil/logfile  $out/basil/${prefix}_logfile
    exec_sys mv    $out/basil/logfile_spatial  $out/basil/${prefix}_logfile_spatial
    exec_sys rm -rf $out/basil/${prefix}_cbf.nii.gz $out/basil/${prefix}_cbf_pv_gm_calib.nii.gz 
    exec_sys rm -rf $out/basil/${prefix}_cbf_pv_wm_calib.nii.gz $out/basil/${prefix}_cbf_pv.nii.gz
    exec_sys rm -rf $out/basil/${prefix}_cbf_spatial.nii.gz $out/basil/${prefix}_cbf_pv_gm.nii.gz 
    exec_sys rm -rf $out/basil/${prefix}_cbf_pv_wm.nii.gz $out/basil/cbf_pv_calib.nii.gz
    
 
  elif [ ${basil_pvc[cxt]} == 0 ]; then
  
    exec_fsl immv  $out/basil/acbv   $out/basil/${prefix}_acbv
    exec_fsl immv  $out/basil/acbv_spatial   $out/basil/${prefix}_acbv_spatial
    exec_fsl immv  $out/basil/cbf   $out/basil/${prefix}_cbf
    exec_fsl immv  $out/basil/cbf_calib   $out/basil/${prefix}_cbf_basil
    exec_fsl immv  $out/basil/cbf_spatial_calib   $out/basil/${prefix}_cbf_basil_spatial
    exec_fsl immv  $out/basil/cbf_spatial  $out/basil/${prefix}_cbf_spatial
    exec_fsl immv  $out/basil/M0   $out/basil/${prefix}_M0
    exec_fsl immv  $out/basil/mask   $out/basil/${prefix}_mask
    exec_sys mv  $out/basil/basil_option.txt  $out/basil/${prefix}_basil_option.txt
    exec_sys mv  $out/basil/logfile  $out/basil/${prefix}_logfile
    exec_sys mv  $out/basil/logfile_spatial  $out/basil/${prefix}_logfile_spatial
    exec_sys rm -rf $out/basil/${prefix}_cbf.nii.gz $out/basil/${prefix}_cbf_pv_gm_calib.nii.gz 
    exec_sys rm -rf $out/basil/${prefix}_cbf_pv_wm_calib.nii.gz $out/basil/${prefix}_cbf_pv.nii.gz
    exec_sys rm -rf $out/basil/${prefix}_cbf_spatial.nii.gz $out/basil/${prefix}_cbf_pv_gm.nii.gz 
    exec_sys rm -rf $out/basil/${prefix}_cbf_pv_wm.nii.gz $out/basil/${prefix}_cbf.nii.gz
    
 
 fi 
 
   neg=( $(exec_fsl fslstats $out/basil/${prefix}_cbf_basil.nii.gz          \
              -k    $out/basil/${prefix}_mask.nii.gz  \
              -u    0                                       \
              -V) )
   echo ${neg[0]}   >> ${negative_voxels_basil[cxt]}

  
  
routine_end

completion
