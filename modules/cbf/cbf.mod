#!/usr/bin/env bash

###################################################################
#  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  #
###################################################################

###################################################################
# SPECIFIC MODULE HEADER
# This module aligns the analyte image to a high-resolution target.
###################################################################
mod_name_short=cbf
mod_name='CEREBRAL BLOOD FLOW MODULE'
mod_head=${XCPEDIR}/core/CONSOLE_MODULE_RC

###################################################################
# GENERAL MODULE HEADER
###################################################################
source ${XCPEDIR}/core/constants
source ${XCPEDIR}/core/functions/library.sh
source ${XCPEDIR}/core/parseArgsMod

###################################################################
# MODULE COMPLETION
###################################################################
completion() {
   source ${XCPEDIR}/core/auditComplete
   source ${XCPEDIR}/core/updateQuality
   source ${XCPEDIR}/core/moduleEnd
}





###################################################################
# OUTPUTS
###################################################################
derivative            meanPerfusion    ${prefix}_meanPerfusion
derivative            perfusion        ${prefix}_perfusion

output                tag_mask         ${prefix}_tag_mask.txt
output                rps_proc         ${prefix}_realignment_transform.1D

qc negative_voxels    negativeVoxels   ${prefix}_negativeVoxels.txt
qc negative_voxels_ts negativeVoxelsTS ${prefix}_negativeVoxelsTS.txt

derivative_set        meanPerfusion    Statistic         mean
derivative            referenceVolumeBrain    ${prefix}_referenceVolumeBrain
input 1dim            rps_proc or rps  as rps

process               perfusion        ${prefix}_perfusion

<<DICTIONARY

meanPerfusion
   The voxelwise estimate of perfusion averaged over all label-
   control volume pairs.
negative_voxels
   The number of grey matter voxels with negative cerebral blood
   flow estimates in the mean perfusion image.
negative_voxels_ts
   The number of grey matter voxels with negative cerebral blood
   flow estimates over all time.
perfusion
   A voxelwise time series of perfusion estimates.
tag_mask
   A 1-dimensional mask indicating whether each volume is tagged
   (1) or untagged (0).

DICTIONARY


###################################################################
# Prepare a mask indicating whether each volume is tagged or
# untagged.
###################################################################
if ! is_1D ${tag_mask[cxt]} \
|| rerun
   then
   routine                    @1    Flagging tagged volumes
   exec_sys rm -f ${tag_mask[cxt]}
   if (( ${cbf_first_tagged[cxt]} == 1 ))
      then
      subroutine              @1.1  First volume is label
      next_label=1
      else
      subroutine              @1.2  First volume is control
      next_label=0
   fi
   nvol=$(exec_fsl fslnvols ${intermediate}.nii.gz)
   cvol=0
   while (( ${cvol} < ${nvol} ))
      do
      echo   ${next_label} >> ${tag_mask[cxt]}
      if    (( next_label == 1 ))
         then
         next_label=0
      elif  (( next_label == 0 ))
         then
         next_label=1
      fi
      (( cvol++ ))
   done
   routine_end
fi

subroutine @1.3 Generate m0 volume 

if ! is_image ${m0[sub]} 
   then 
   m0=${out}/cbf/${prefix}_m0.nii.gz
   cbf_m0_scale[cxt]=1
   if (( ${cbf_first_tagged[cxt]} == 1 ))
      then
      exec_afni 3dcalc -prefix ${m0}  -a ${intermediate}.nii.gz'[0..$(2)]' -expr "a" 2>/dev/null   
      else
      exec_afni 3dcalc -prefix ${m0}  -a ${intermediate}.nii.gz'[1..$(2)]' -expr "a" 2>/dev/null 
   fi
   exec_fsl fslmaths ${m0} -Tmean ${m0}
   output m0  ${out}/cbf/${prefix}_m0.nii.gz
else
   m0=${out}/cbf/${prefix}_m0.nii.gz
   exec_fsl fslmaths ${m0[sub]} -Tmean ${m0}
   output m0  ${out}/cbf/${prefix}_m0.nii.gz
fi

subroutine @1.3 create mask

exec_ants antsApplyTransforms -i ${structmask[sub]} -r ${referenceVolume[sub]} \
   -t ${struct2seq[sub]} -o ${out}/cbf/temp_mask.nii.gz  -n NearestNeighbor 

exec_fsl fslmaths ${referenceVolume[sub]} -mul ${out}/cbf/temp_mask.nii.gz \
         -bin ${out}/cbf/${prefix}_mask.nii.gz 
output mask ${out}/cbf/${prefix}_mask.nii.gz 


   
exec_fsl fslmaths ${referenceVolume[sub]} -mul ${out}/cbf/temp_mask.nii.gz \
                    ${out}/cbf/${prefix}_referenceVolumeBrain.nii.gz
 
output referenceVolumeBrain ${out}/cbf/${prefix}_referenceVolumeBrain.nii.gz


###################################################################
# Compute cerebral blood flow.
###################################################################
if ! is_image ${meanPerfusion[cxt]} \
|| ! is_image ${perfusion[cxt]}     \
|| rerun
   then
   routine                    @2    Computing cerebral blood flow
   case ${cbf_perfusion[cxt]} in
   
   casl)
      subroutine              @2.1a PCASL -- Pseudocontinuous ASL
      subroutine              @2.1b Input: ${intermediate}.nii.gz
      subroutine              @2.1c M0: ${mo[cxt]}
      subroutine              @2.1d Tags: ${tag_mask[cxt]}
      subroutine              @2.1e M0 scale: ${cbf_m0_scale[cxt]}
      subroutine              @2.1f Partition coefficient: ${cbf_lambda[cxt]}
      subroutine              @2.1g Post-labelling delay: ${cbf_pld[cxt]}
      subroutine              @2.1h Label duration: ${cbf_tau[cxt]}
      subroutine              @2.1i Blood T1: ${cbf_t1blood[cxt]}
      subroutine              @2.1j Labelling efficiency: ${cbf_alpha[cxt]}
      exec_sys rm -f ${intermediate}_perfusion*
      exec_xcp perfusion.R                   \
         -i    ${intermediate}.nii.gz        \
         -m    ${m0[cxt]}  \
         -v    ${tag_mask[cxt]}              \
         -o    ${intermediate}_perfusion     \
         -s    ${cbf_m0_scale[cxt]}          \
         -l    ${cbf_lambda[cxt]}            \
         -d    ${cbf_pld[cxt]}               \
         -r    ${cbf_tau[cxt]}               \
         -t    ${cbf_t1blood[cxt]}           \
         -a    ${cbf_alpha[cxt]}
      ;;
      
   pasl)
      subroutine              @2.2a PASL -- Pulsed ASL
      subroutine              @2.1b Input: ${intermediate}.nii.gz
      subroutine              @2.1c M0:  ${mo[cxt]}
      subroutine              @2.1d Tags: ${tag_mask[cxt]}
      subroutine              @2.1e M0 scale: ${cbf_m0_scale[cxt]}
      subroutine              @2.1f Partition coefficient: ${cbf_lambda[cxt]}
      subroutine              @2.1g Invertion time: ${cbf_ti[cxt]}
      subroutine              @2.1h bolus duration: ${cbf_ti1[cxt]}
      subroutine              @2.1i Blood T1: ${cbf_t1blood[cxt]}
      subroutine              @2.1j Labelling efficiency: ${cbf_alpha[cxt]}
      exec_sys rm -f ${intermediate}_perfusion*
      exec_xcp perfusion_pasl.R                   \
         -i    ${intermediate}.nii.gz        \
         -m    ${m0[cxt]}  \
         -v    ${tag_mask[cxt]}              \
         -o    ${intermediate}_perfusion     \
         -s    ${cbf_m0_scale[cxt]}          \
         -l    ${cbf_lambda[cxt]}            \
         -b    ${cbf_ti1[cxt]}               \
         -r    ${cbf_ti[cxt]}               \
         -t    ${cbf_t1blood[cxt]}           \
         -a    ${cbf_alpha[cxt]}
      ;;
      
   esac
   routine_end
   
   
   
   
   
   ################################################################
   # Reorganise outputs and compute quality metrics
   ################################################################
   routine                    @3    Quality and cleanup
   subroutine                 @3.1  Reorganising output
   exec_fsl fslmaths  ${intermediate}_perfusion_mean.nii.gz -mul \
               ${mask[cxt]} ${meanPerfusion[cxt]}
   exec_fsl fslmaths ${intermediate}_perfusion_ts.nii.gz -mul \
               ${mask[cxt]} ${perfusion[cxt]}
   subroutine                 @3.2  Computing grey matter boundary
   exec_xcp    val2mask.R           \
      -i       ${segmentation[sub]} \
      -v       ${cbf_gm_val[cxt]}   \
      -o       ${intermediate}_gm.nii.gz
   warpspace                        \
      ${intermediate}_gm.nii.gz     \
      ${intermediate}_gm_${space[sub]}.nii.gz \
      ${structural[sub]}:${space[sub]} \
      NearestNeighbor
   subroutine                 @3.3  Counting negative voxels
   neg=( $(exec_fsl fslstats ${meanPerfusion[cxt]}          \
              -k    ${intermediate}_gm_${space[sub]}.nii.gz \
              -u    0                                       \
              -V) )
   echo ${neg[0]}   >> ${negative_voxels[cxt]}
   neg=( $(exec_fsl fslstats ${perfusion[cxt]}              \
              -k    ${intermediate}_gm_${space[sub]}.nii.gz \
              -u    0                                       \
              -V) )
   echo ${neg[0]}   >> ${negative_voxels_ts[cxt]}
   routine_end
fi
   
routine                       @4    Selecting realignment parameters
subroutine                    @4.1  Averaging over tagged/untagged pairs
exec_xcp realignment.R -m ${rps[cxt]} -t mean -o ${outdir}/${prefix}
routine_end





completion
