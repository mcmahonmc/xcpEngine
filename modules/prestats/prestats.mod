#!/usr/bin/env bash

###################################################################
#  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  ⊗  #
###################################################################

###################################################################
# SPECIFIC MODULE HEADER
# This module preprocesses fMRI data.
###################################################################
mod_name_short=prestats
mod_name='FMRI PREPROCESSING MODULE'
mod_head=${XCPEDIR}/core/CONSOLE_MODULE_RC
source ${XCPEDIR}/core/functions/library_func.sh

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
   contains ${prestats_process[cxt]} 'DMT' && configure demeaned 1
   is_1D    ${tmask[cxt]}                  && configure censored 1
   unset  confproc
   source ${XCPEDIR}/core/auditComplete
   source ${XCPEDIR}/core/updateQuality
   source ${XCPEDIR}/core/moduleEnd
}





###################################################################
# OUTPUTS
###################################################################
derivative  referenceVolumeBrain    ${prefix}_referenceVolumeBrain
derivative  meanIntensityBrain      ${prefix}_meanIntensityBrain
derivative  mask                    ${prefix}_mask

derivative_set    mask Type         Mask

output      mcdir                   mc
output      rps                     mc/${prefix}_realignment.1D
output      abs_rms                 mc/${prefix}_absRMS.1D
output      abs_mean_rms            mc/${prefix}_absMeanRMS.txt
output      rel_rms                 mc/${prefix}_relRMS.1D
output      rmat                    mc/${prefix}.mat
output      motion_vols             mc/${prefix}_nFramesHighMotion.txt
output      confmat                 ${prefix}_confmat.1D
output      referenceVolume         ${prefix}_referenceVolume.nii.gz
output      meanIntensity           ${prefix}_meanIntensity.nii.gz
output      fmriprepconf            ${prefix}_fmriconf.tsv



configure   demeaned                0

qc rel_max_rms    relMaxRMSMotion   mc/${prefix}_relMaxRMS.txt
qc rel_mean_rms   relMeanRMSMotion  mc/${prefix}_relMeanRMS.txt

qc coreg_cross_corr  coregCrossCorr ${prefix}_coregCrossCorr.txt
qc coreg_coverage    coregCoverage  ${prefix}_coregCoverage.txt
qc coreg_jaccard     coregJaccard   ${prefix}_coregJaccard.txt
qc coreg_dice        coregDice      ${prefix}_coregDice.txt

smooth_spatial_prime                ${prestats_smo[cxt]}
ts_process_prime
temporal_mask_prime

input       demeaned
input       confmat as confproc
input       referenceVolume

final       preprocessed            ${prefix}_preprocessed

<< DICTIONARY

abs_mean_rms
   The absolute RMS displacement, averaged over all volumes.
abs_rms
   Absolute root mean square displacement.
censor
   A flag indicating whether the current pipeline should include
   framewise censoring. This instruction is passed to the regress
   module, which handles the censoring protocol.
censored
   A variable that specifies whether censoring has been primed in
   the current module.
confmat
   The confound matrix after filtering and censoring.
confproc
   A pointer to the working version of the confound matrix.
dvars
   The DVARS, a framewise index of the rate of change of the global
   BOLD signal
fd
   Framewise displacement values, computed as the absolute sum of
   realignment parameter first derivatives.
mcdir
   The directory containing motion realignment output.
mask
   A spatial mask of binary values, indicating whether a voxel
   should be analysed as part of the brain; the definition of brain
   tissue is often fairly liberal.
meanIntensity
   The mean intensity over time of functional data, after it has
   been realigned to the example volume.
motion_vols
   A quality control file that specifies the number of volumes that
   exceeded the maximum motion criterion. If censoring is enabled,
   then this will be the same number of volumes that are to be
   censored.
preprocessed
   The final output of the module, indicating its successful
   completion.
referenceVolume
   An example volume extracted from EPI data, typically one of the
   middle volumes, though another may be selected if the middle
   volume is corrupted by motion-related noise. This is used as the
   reference volume during motion realignment.
rel_max_rms
   The maximum single-volume value of relative RMS displacement.
rel_mean_rms
   The relative RMS displacement, averaged over all volumes.
rel_rms
   Relative root mean square displacement.
rmat
   A directory containing rigid transforms applied to each volume
   in order to realign it with the reference volume
rps
   Framewise values of the 6 realignment parameters.
tmask
   A temporal mask of binary values, indicating whether the volume
   survives motion censorship.
   
DICTIONARY



routine                 @0    Ensure matching orientation
subroutine              @0.1a Input: ${intermediate}.nii.gz
subroutine              @0.1b Template: ${template}
subroutine              @0.1c Output root:

subroutine @0.1d checking the orientation of img and template

native_orientation=$(exec_afni 3dinfo -orient ${intermediate}.nii.gz)

template_orientation=$(exec_afni 3dinfo -orient ${template})

echo "NATIVE:${native_orientation} TEMPLATE:${template_orientation}"

full_intermediate=$(ls ${intermediate}.nii* | head -n 1)

if [ "${native_orientation}" != "${template_orientation}" ]
then
    subroutine @0.1e img and template orientation are not the same
    subroutine @0.1f make it: "${native_orientation} -> ${template_orientation}"
    exec_afni 3dresample -orient ${template_orientation} \
              -inset ${intermediate}.nii.gz \
              -prefix ${intermediate}_${template_orientation}.nii.gz

    #intermediate=${intermediate}_${template_orientation}
    #intermediate_root=${intermediate}
     exec_fsl immv  ${intermediate}_${template_orientation}.nii.gz ${intermediate}.nii.gz  \
                        
    intermediate_root=${intermediate}
else

    subroutine  @0.1f "NOT re-orienting native bcos they are the same"

fi

###################################################################
# The variable 'buffer' stores the processing steps that are
# already complete; it becomes the expected ending for the final
# image name and is used to verify that prestats has completed
# successfully.
###################################################################
unset buffer

subroutine                    @0.1
###################################################################
# Parse the control sequence to determine what routine to run next.
# Available routines include:
#  * FMP: fmriprep
#  * DVO: discard volumes
#  * MPR: compute motion-related variables, including RPs
#  * MCO: correct for subject motion
#  * STM: slice timing correction
#  * BXT: brain extraction
#  * DMT: demean and detrend time series
#  * DSP: despike timeseries
#  * SPT: spatial filter
#  * TMP: temporal filter
#  * REF: obtain references, but don't do any processing
###################################################################
rem=${prestats_process[cxt]}
while (( ${#rem} > 0 ))
   do
   ################################################################
   # * Extract the three-letter routine code from the user-
   #   specified control sequence.
   # * This three-letter code determines what routine is run next.
   # * Remove the code from the remaining control sequence.
   ################################################################
   cur=${rem:0:3}
   rem=${rem:4:${#rem}}
   buffer=${buffer}_${cur}
   case ${cur} in
            FMP)
        ########################################
        # obtain fmriprep mask etc and struct
  
        ########################################
         
         routine @ getting data from frmiprep directory 
        exec_fsl immv ${intermediate} ${intermediate}_${cur}   
        imgprt=${img1[sub]%_*_*_*}; conf="_desc-confounds_regressors.tsv"
        exec_sys cp ${imgprt}${conf} $out/prestats/${prefix}_fmriconf.tsv
        imgprt2=${img1[sub]%_*_*}; mskpart="_desc-brain_mask.nii.gz"
        mask1=${imgprt2}${mskpart}; maskpart2=${mask1#*_*_*_*}
        refpart="_boldref.nii.gz"; refvol=${imgprt2}${refpart}

         strucn="${img1[sub]%/*/*}";
         if [[ -f  $(ls ${strucn}/anat/*from-MNI152NLin2009cAsym_to-T1w_mode-image_xfm.h5 2>/dev/null ) ]]; then  
                  strucn=${strucn}
         else

          anatdir=$strucn/../
          
          strucn=${anatdir}

         fi
         
         if [[ -d ${antsct[sub]} ]]; then
               subroutine @ generate mask and struct/structhead 
              
               structmask=$(ls -d ${strucn}/anat/*${maskpart2})

               subroutine @ resampling the ref vol to template orientation
               exec_afni 3dresample -orient ${template_orientation} -inset ${refvol} -prefix  \
                   ${out}/prestats/${prefix}_referenceVolume.nii.gz -overwrite
             
               output referenceVolume  ${out}/prestats/${prefix}_referenceVolume.nii.gz
             

               exec_afni 3dresample -orient ${template_orientation} \
               -inset ${mask1} -prefix ${prefix}_imgmask.nii.gz -overwrite

               exec_afni 3dresample -master ${out}/prestats/${prefix}_referenceVolume.nii.gz \
                  -inset ${structmask}  -prefix ${prefix}_structmask.nii.gz -overwrite

               exec_fsl fslmaths ${prefix}_imgmask.nii.gz -mul ${prefix}_structmask.nii.gz \
                      ${out}/prestats/${prefix}_mask.nii.gz

                output mask  ${out}/prestats/${prefix}_mask.nii.gz
                rm ${prefix}_structmask.nii.gz
                rm ${prefix}_imgmask.nii.gz

               exec_afni 3dresample -master ${mask[cxt]} \
                   -inset ${segmentation[sub]}  \
                  -prefix ${out}/prestats/${prefix}_segmentation.nii.gz -overwrite

               output segmentation  ${out}/prestats/${prefix}_segmentation.nii.gz

               exec_fsl fslmaths  ${mask[cxt]} -mul \
                   ${referenceVolume[cxt]} \
                   ${out}/prestats/${prefix}_referenceVolumeBrain.nii.gz 
                   
               output referenceVolumeBrain ${out}/prestats/${prefix}_referenceVolumeBrain.nii.gz
   
             
               exec_afni 3dresample -master ${referenceVolume[cxt]} \
                   -inset ${struct[sub]}   -prefix ${out}/prestats/${prefix}_struct.nii.gz -overwrite
 
               output struct  ${out}/prestats/${prefix}_struct.nii.gz
               output struct_head ${out}/prestats/${prefix}_struct.nii.gz

                
 
             
             
               subroutine        @  generate new ${spaces[sub]} with spaceMetadata

               rm -f ${spaces[sub]}
               echo '{}'  >> ${spaces[sub]}
                       
               mnitopnc=" $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/MNI-PNC_0Affine.mat)
                        $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/MNI-PNC_1Warp.nii.gz)"
               pnc2mni=" $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/PNC-MNI_0Warp.nii.gz)
                        $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/PNC-MNI_1Affine.mat)"
               mnitopnc=$( echo ${mnitopnc})
               pnc2mni=$(echo ${pnc2mni})
               mnitopnc=${mnitopnc// /,}
               pnc2mni=${pnc2mni// /,}

               ${XCPEDIR}/utils/spaceMetadata          \
                    -o ${spaces[sub]}                 \
                    -f MNI%2x2x2:${XCPEDIR}/space/MNI/MNI-2x2x2.nii.gz        \
                    -m PNC%2x2x2:${XCPEDIR}/space/PNC/PNC-2x2x2.nii.gz \
                    -x ${pnc2mni}                               \
                    -i ${mnitopnc}                               \
                    -s ${spaces[sub]} 2>/dev/null


              hd=',MapHead='${struct_head[cxt]}
              subj2temp="   $(ls -d ${antsct[sub]}/*SubjectToTemplate0GenericAffine.mat)
                           $(ls -d ${antsct[sub]}/*SubjectToTemplate1Warp.nii.gz)"
              temp2subj="   $(ls -d ${antsct[sub]}/*TemplateToSubject0Warp.nii.gz) 
                          $(ls -d ${antsct[sub]}/*TemplateToSubject1GenericAffine.mat)"
              subj2temp=$( echo ${subj2temp})
              temp2subj=$(echo ${temp2subj})
              subj2temp=${subj2temp// /,}
              temp2subj=${temp2subj// /,}

              ${XCPEDIR}/utils/spaceMetadata          \
                    -o ${spaces[sub]}                 \
                    -f ${standard}:${template}        \
                    -m ${structural[sub]}:${struct[cxt]}${hd} \
                    -x ${subj2temp}                               \
                    -i ${temp2subj}                               \
                    -s ${spaces[sub]} 2>/dev/null
               
             
                intermediate=${intermediate}_${cur} 
               

         
               
          else 
          
               
               mni2t1=$(ls -f  $strucn/anat/*from-MNI152NLin2009cAsym_to-T1w_mode-image_xfm.h5)
               t12mni=$(ls -f  $strucn/anat/*from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5)
         
                # check if the input image has MNI and convert to T1w
                 string1='MNI152'; b1=$(basename ${img1[sub]})
                      if [[ ${b1} =~ ${string1} ]]; then 
                      ## check if the confounmatix is present and the mask 
             
                      struct1=$( ls -d $strucn/anat/*MNI*desc-preproc_T1w.nii.gz)
                      segmentation1=$(ls -d  $strucn/anat/*MNI*dseg.nii.gz)
                      structmask=$(ls -d  $strucn/anat/*MNI*desc-brain_mask.nii.gz)
                      onetran=${XCPEDIR}/utils/oneratiotransform.txt
  
                      subroutine        @ checking refvolume and structural orientation
                      exec_afni 3dresample -orient  ${template_orientation} \
                           -inset ${refvol} -prefix  ${out}/prestats/${prefix}_referenceVolume.nii.gz -overwrite

                      output referenceVolume  ${out}/prestats/${prefix}_referenceVolume.nii.gz

                      exec_afni 3dresample -master  ${referenceVolume[cxt]} \
                           -inset ${struct1} -prefix  ${out}/prestats/${prefix}_struct.nii.gz -overwrite

                      output struct_head ${out}/prestats/${prefix}_struct.nii.gz
                      output struct  ${out}/prestats/${prefix}_struct.nii.gz
                      exec_afni 3dresample -master  ${referenceVolume[cxt]} \
                           -inset ${struct[cxt]} -prefix  ${out}/prestats/${prefix}_struct.nii.gz -overwrite
                       
                      exec_afni 3dresample -master  ${referenceVolume[cxt]} \
                           -inset ${segmentation1} -prefix  ${out}/prestats/${prefix}_segmentation.nii.gz -overwrite

                      output segmentation  ${out}/prestats/${prefix}_segmentation.nii.gz

                       subroutine        @  generate mask and referenceVolumeBrain 
                     

                       exec_afni 3dresample -master ${referenceVolume[cxt]} \
                          -inset ${structmask}  -prefix ${prefix}_structmask.nii.gz -overwrite

                      exec_fsl fslmaths ${mask1} -mul ${prefix}_structmask.nii.gz \
                      ${out}/prestats/${prefix}_mask.nii.gz

                      output mask  ${out}/prestats/${prefix}_mask.nii.gz
                       exec_afni 3dresample -master  ${referenceVolume[cxt]} \
                           -inset ${mask[cxt]} -prefix  ${out}/prestats/${prefix}_mask.nii.gz -overwrite

                      rm ${prefix}_structmask.nii.gz

                      exec_fsl fslmaths  ${mask[cxt]} -mul ${referenceVolume[cxt]} \
                          ${out}/prestats/${prefix}_referenceVolumeBrain.nii.gz 
                          
                      output referenceVolumeBrain ${out}/prestats/${prefix}_referenceVolumeBrain.nii.gz 

                
                      subroutine        @  generate new ${spaces[sub]} with spaceMetadata

                  
                      output struct_head ${out}/prestats/${prefix}_struct.nii.gz

                       rm -f ${spaces[sub]}
                       echo '{}'  >> ${spaces[sub]}
                       mnitopnc=" $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/MNI-PNC_0Affine.mat)
                                    $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/MNI-PNC_1Warp.nii.gz)"
                       pnc2mni=" $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/PNC-MNI_0Warp.nii.gz)
                                    $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/PNC-MNI_1Affine.mat)"
                       mnitopnc=$( echo ${mnitopnc})
                       pnc2mni=$(echo ${pnc2mni})
                       mnitopnc=${mnitopnc// /,}
                       pnc2mni=${pnc2mni// /,}

                       ${XCPEDIR}/utils/spaceMetadata          \
                         -o ${spaces[sub]}                 \
                         -f MNI%2x2x2:${XCPEDIR}/space/MNI/MNI-2x2x2.nii.gz        \
                         -m PNC%2x2x2:${XCPEDIR}/space/PNC/PNC-2x2x2.nii.gz \
                         -x ${pnc2mni}                               \
                         -i ${mnitopnc}                               \
                         -s ${spaces[sub]} 2>/dev/null
                       hd=',MapHead='${struct_head[cxt]}
                   
                       ${XCPEDIR}/utils/spaceMetadata          \
                         -o ${spaces[sub]}                 \
                         -f ${standard}:${template}        \
                         -m ${structural[sub]}:${struct[cxt]}${hd} \
                         -x ${onetran}                               \
                         -i ${onetran}                               \
                         -s ${spaces[sub]} 2>/dev/null

                         
                         intermediate=${intermediate}_${cur} 
                
   
                else 
                    struct1=$(find $strucn/anat/ -type f -name "*desc-preproc_T1w.nii.gz" -not -path  "*MNI*" )
                    segmentation1=$(find $strucn/anat/ -type f -name "*dseg.nii.gz" -not -path  "*MNI*" -not -path "*aseg*")
                    structmask=$(find $strucn/anat/ -type f -name "*desc-brain_mask.nii.gz" -not -path  "*MNI*")
                    
                 exec_afni 3dresample -orient ${template_orientation} -inset ${refvol} \
                       -prefix  ${out}/prestats/${prefix}_referenceVolume.nii.gz -overwrite
                    output referenceVolume  ${out}/prestats/${prefix}_referenceVolume.nii.gz
                   

                   exec_afni 3dresample -orient ${template_orientation} \
                    -inset ${mask1} -prefix  ${prefix}_imgmask.nii.gz -overwrite
                   

                   exec_afni 3dresample -master ${referenceVolume[cxt]} \
                     -inset ${structmask} -prefix ${prefix}_structmask.nii.gz -overwrite

                   exec_fsl fslmaths  ${prefix}_imgmask.nii.gz -mul ${prefix}_structmask.nii.gz ${out}/prestats/${prefix}_mask.nii.gz
                   output mask  ${out}/prestats/${prefix}_mask.nii.gz
                    rm ${prefix}_structmask.nii.gz ${prefix}_imgmask.nii.gz

                  exec_afni 3dresample -master ${referenceVolume[cxt]} -inset ${segmentation1}   \
                         -prefix ${out}/prestats/${prefix}_segmentation.nii.gz -overwrite
              
                  output segmentation  ${out}/prestats/${prefix}_segmentation.nii.gz

                  exec_afni 3dresample -master ${referenceVolume[cxt]} -inset ${struct1}   \
                                -prefix ${out}/prestats/${prefix}_struct.nii.gz -overwrite

                  output struct_head ${out}/prestats/${prefix}_struct.nii.gz
                  output struct ${out}/prestats/${prefix}_struct.nii.gz
                
                exec_fsl fslmaths  ${mask[cxt]} -mul ${referenceVolume[cxt]} \
                         ${out}/prestats/${prefix}_referenceVolumeBrain.nii.gz 
                output referenceVolumeBrain ${out}/prestats/${prefix}_referenceVolumeBrain.nii.gz
                 
                
                subroutine        @  generate new ${spaces[sub]} with spaceMetadata
                rm -f ${spaces[sub]}
                echo '{}'  >> ${spaces[sub]}

                mnitopnc="    $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/MNI-PNC_0Affine.mat)
                           $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/MNI-PNC_1Warp.nii.gz)"
                pnc2mni="  $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/PNC-MNI_0Warp.nii.gz)
                          $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/PNC-MNI_1Affine.mat)"
                       
                       mnitopnc=$( echo ${mnitopnc})
                       pnc2mni=$(echo ${pnc2mni})
                       mnitopnc=${mnitopnc// /,}
                       pnc2mni=${pnc2mni// /,}

                       ${XCPEDIR}/utils/spaceMetadata  \
                         -o ${spaces[sub]}                 \
                         -f MNI%2x2x2:${XCPEDIR}/space/MNI/MNI-2x2x2.nii.gz        \
                         -m PNC%2x2x2:${XCPEDIR}/space/PNC/PNC-2x2x2.nii.gz \
                         -x ${pnc2mni} -i ${mnitopnc}     \
                         -s ${spaces[sub]} 2>/dev/null

                hd=',MapHead='${struct_head[cxt]}

               ${XCPEDIR}/utils/spaceMetadata          \
                         -o ${spaces[sub]}                         \
                         -f ${standard}:${template}                \
                         -m ${structural[sub]}:${struct[cxt]}${hd} \
                         -x ${t12mni}                                \
                         -i ${mni2t1}                               \
                         -s ${spaces[sub]} 2>/dev/null

               
                intermediate=${intermediate}_${cur} 
                
                
            fi 

       fi
    subroutine        @  Quality assessment
    
   
    registration_quality=( $(exec_xcp \
      maskOverlap.R           \
      -m ${segmentation[cxt]}   \
      -r ${referenceVolumeBrain[cxt]}) )
    echo  ${registration_quality[0]} > ${coreg_cross_corr[cxt]}
    echo  ${registration_quality[1]} > ${coreg_coverage[cxt]}
    echo  ${registration_quality[2]} > ${coreg_jaccard[cxt]}
    echo  ${registration_quality[3]} > ${coreg_dice[cxt]}

      routine_end 
       ;;

      NST)
         
          routine              @1 Removing non-steady state volumes
         #exec_fsl immv ${intermediate} ${intermediate}_${cur}
         exec_xcp removenonsteady.py -i  ${intermediate}.nii.gz  \
                     -t $out/prestats/${prefix}_fmriconf.tsv \
                     -o $out/prestats/prepocessed.nii.gz -s $out/prestats/${prefix}_fmriconf.tsv
        
        exec_fsl immv $out/prestats/prepocessed.nii.gz  ${intermediate}_${cur}.nii.gz
         intermediate=${intermediate}_${cur}
                rm -rf $out/prestats/prepocessed.nii.gz
          
        routine_end
       ;;
      
      ASL)
       routine              @1  Preparing asl data
       #exec_fsl immv ${intermediate} ${intermediate}_${cur}
      if  ! is_image ${intermediate}_${cur}.nii.gz \
         || rerun 
         then
         subroutine        @1.1  Reading the structural and segmentation images 
         struct1=$(find ${anatdir[sub]}/ -type f -name "*desc-preproc_T1w.nii.gz" -not -path  "*MNI*" )
         seg1=$(find ${anatdir[sub]}/ -type f -name "*dseg.nii.gz" -not -path  "*MNI*" -not -path "*aseg*")
         structmask=$(find ${anatdir[sub]}/ -type f -name "*desc-brain_mask.nii.gz" -not -path  "*MNI*")
         wm_fmp=$(find ${anatdir[sub]}/ -type f -name "*WM_probseg.nii.gz" -not -path  "*MNI*" -not -path "*aseg*" )
         csf_fmp=$(find ${anatdir[sub]}/ -type f -name "*CSF_probseg.nii.gz" -not -path  "*MNI*" -not -path "*aseg*")
         gm_fmp=$(find ${anatdir[sub]}/ -type f -name "*GM_probseg.nii.gz" -not -path  "*MNI*" -not -path "*aseg*")
         mni2t1=$(ls -f  ${anatdir[sub]}/*from-MNI152NLin2009cAsym_to-T1w_mode-image_xfm.h5)
         t12mni=$(ls -f  ${anatdir[sub]}/*from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5)

         subroutine      @1.2  Reorient  structural  images to ${template_orientation}
         exec_afni 3dresample -orient ${template_orientation} \
              -inset ${struct1} \
              -prefix ${out}/prestats/${prefix}_struct.nii.gz 
         output struct  ${out}/prestats/${prefix}_struct.nii.gz
         output struct_head  ${out}/prestats/${prefix}_struct.nii.gz
          
         exec_afni 3dresample -orient ${template_orientation} \
              -inset ${seg1} \
              -prefix ${out}/prestats/${prefix}_segmentation.nii.gz 
         output segmentation  ${out}/prestats/${prefix}_segmentation.nii.gz
         output coreg_seg ${out}/prestats/${prefix}_segmentation.nii.gz

         exec_afni 3dresample -orient ${template_orientation} \
              -inset ${structmask} \
              -prefix ${out}/prestats/${prefix}_structmask.nii.gz
         output  structmask ${out}/prestats/${prefix}_structmask.nii.gz
         exec_afni 3dresample -orient ${template_orientation} \
              -inset ${wm_fmp} \
              -prefix ${out}/prestats/${prefix}_whitematter.nii.gz
         output wm  ${out}/prestats/${prefix}_whitematter.nii.gz

         exec_afni 3dresample -orient ${template_orientation} \
              -inset ${csf_fmp} \
              -prefix ${out}/prestats/${prefix}_csf.nii.gz
         output csf  ${out}/prestats/${prefix}_csf.nii.gz

         exec_afni 3dresample -orient ${template_orientation} \
              -inset ${gm_fmp} \
              -prefix ${out}/prestats/${prefix}_greymatter.nii.gz
         output gm  ${out}/prestats/${prefix}_greymatter.nii.gz

      if  is_image ${m0[sub]}
      then
      exec_afni 3dresample -orient ${template_orientation} \
              -inset {m0[sub]} \
              -prefix ${out}/prestats/${prefix}_m0.nii.gz
      output m0  ${out}/prestats/${prefix}_m0.nii.gz
      fi
      subroutine        @  generate new ${spaces[sub]} with spaceMetadata
                rm -f ${spaces[sub]}
                echo '{}'  >> ${spaces[sub]}

                mnitopnc="    $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/MNI-PNC_0Affine.mat)
                           $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/MNI-PNC_1Warp.nii.gz)"
                pnc2mni="  $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/PNC-MNI_0Warp.nii.gz)
                          $(ls -d ${XCPEDIR}/space/PNC/PNC_transforms/PNC-MNI_1Affine.mat)"
                       
                       mnitopnc=$( echo ${mnitopnc})
                       pnc2mni=$(echo ${pnc2mni})
                       mnitopnc=${mnitopnc// /,}
                       pnc2mni=${pnc2mni// /,}

                       ${XCPEDIR}/utils/spaceMetadata  \
                         -o ${spaces[sub]}                 \
                         -f MNI%2x2x2:${XCPEDIR}/space/MNI/MNI-2x2x2.nii.gz        \
                         -m PNC%2x2x2:${XCPEDIR}/space/PNC/PNC-2x2x2.nii.gz \
                         -x ${pnc2mni} -i ${mnitopnc}     \
                         -s ${spaces[sub]} 2>/dev/null

                hd=',MapHead='${struct_head[cxt]}

               ${XCPEDIR}/utils/spaceMetadata          \
                         -o ${spaces[sub]}                         \
                         -f ${standard}:${template}                \
                         -m ${structural[sub]}:${struct[cxt]}${hd} \
                         -x ${t12mni}                                \
                         -i ${mni2t1}                               \
                         -s ${spaces[sub]} 2>/dev/null

         exec_sys ln -sf ${intermediate}.nii.gz ${intermediate}_${cur}.nii.gz
         intermediate=${intermediate}_${cur}
      fi 
        
       ;;
      
      DVO)
         ##########################################################
         # DVO discards the first n volumes of the scan, as
         # specified by user input.
         #
         # If dvols is positive, discard the first n volumes
         # from the BOLD time series.
         # If dvols is negative, discard the last n volumes
         # from the BOLD time series.
         ##########################################################
         routine              @1    Discarding ${prestats_dvols[cxt]} volumes
         if ! is_image ${intermediate}_${cur}.nii.gz \
         || rerun
            then
            nvol=$(exec_fsl fslnvols ${intermediate}.nii.gz)
            subroutine        @1.1  [Total original volumes = ${nvol}]
            if is+integer ${prestats_dvols[cxt]}
               then
               subroutine     @1.2  [Discarding initial volumes]
               vol_begin=${prestats_dvols[cxt]}
               vol_end=$(( ${nvol} - ${prestats_dvols[cxt]} ))
            elif is_integer ${prestats_dvols[cxt]}
               then
               subroutine     @1.3  [Discarding final volumes]
               vol_begin=0
               vol_end=$(( ${nvol} + ${prestats_dvols[cxt]} ))
            fi
            subroutine        @1.4  [Primary analyte image]
            proc_fsl  ${intermediate}_${cur}.nii.gz \
               fslroi ${intermediate}.nii.gz \
               %OUTPUT                       \
               ${vol_begin} ${vol_end}
         fi
         ##########################################################
         # Repeat for any derivatives of the BOLD time series that
         # are also time series.
         #
         # Why? Unless the number of volumes in the BOLD time
         # series and in derivative time series -- for instance,
         # local regressors -- is identical, any linear model
         # incorporating the derivatives as predictors would
         # introduce a frameshift error; this may result in
         # incorrect estimates or even a failure to compute
         # parameter estimates for the model.
         #
         # In many cases, discarding of initial volumes represents
         # the first stage of fMRI processing. In these cases,
         # the derivatives index will be empty, and the prestats
         # module should never enter the conditional block below.
         ##########################################################
         subroutine           @1.5
         apply_exec timeseries ${intermediate}_${cur}_%NAME ECHO:Name \
            fsl     fslroi     %INPUT %OUTPUT  ${vol_begin} ${vol_end}
         ##########################################################
         # Compute the updated volume count.
         ##########################################################
         intermediate=${intermediate}_${cur}
         nvol=$(exec_fsl fslnvols ${intermediate}.nii.gz)
         subroutine           @1.6  [New total volumes = ${nvol}]
         routine_end
         ;;
      
      
      
      
      
      MPR)
         ##########################################################
         # MPR computes motion-related variables, such as
         # realignment parameters and framewise displacement.
         #
         # Prime the analytic pipeline for motion censoring, if
         # the user has requested it.
         #
         # Why is this step separate from motion correction?
         #  * Recent analyses have suggested that correction for
         #    slice timing can introduce error into motion
         #    parameter estimates.
         #  * Therefore, it is desirable to compute realignment
         #    parameters prior to slice timing correction.
         #  * However, slice timing correction should probably be
         #    performed on data that has not undergone realignment,
         #    since realignment will move brain regions into slices
         #    different from the ones in which they were acquired.
         #  * Therefore, the recommended processing order is:
         #    MPR STM MCO
         #
         # This step introduces a degree of redundancy to pipelines
         # that do not include slice timing correction.
         ##########################################################
         routine              @2    Computing realignment parameters
         ##########################################################
         # Determine whether a reference functional image already
         # exists. If it does not, extract it from the timeseries
         # midpoint for use as a reference in realignment.
         ##########################################################
         

         if ! is_image ${referenceVolume[sub]} \
         || rerun
            then
            subroutine        @2.1.1 [Extracting reference volume]
            nvol=$(exec_fsl fslnvols ${intermediate}.nii.gz)
            midpt=$(( ${nvol} / 2))
            exec_fsl \
               fslroi ${intermediate}.nii.gz \
               ${intermediate}-reference.nii.gz \
               ${midpt} 1
         else
            subroutine        @2.1.2 [Reference volume: ${referenceVolume[sub]}]
            add_reference     referenceVolume[$sub] ${prefix}_referenceVolume
            exec_sys ln -sf   ${referenceVolume[sub]} \
                              ${intermediate}-reference.nii.gz
         fi
         if ! is_image ${intermediate}_${cur}.nii.gz \
         || rerun
            then
            #######################################################
            # Run MCFLIRT targeting the reference volume to compute
            # the realignment parameters.
            #
            # Output is temporarily placed into the main prestats
            # module output directory; it will be moved into the
            # MC directory.
            #######################################################
            subroutine        @2.2  [Computing realignment parameters]
            proc_fsl    ${intermediate}_mc.nii.gz  \
               mcflirt -in ${intermediate}.nii.gz  \
               -out     ${intermediate}_mc         \
               -reffile ${intermediate}-reference.nii.gz \
               -plots      -rmsrel     -rmsabs     \
               -spline_final
            #######################################################
            # Create the MC directory, and move outputs to their
            # targets.
            #
            # For relative root mean square motion, prepend a
            # value of 0 by convention for the first volume.
            # FSL may change its pipeline in the future so that
            # it automatically does this. If this occurs, then
            # this must be changed.
            #######################################################
            subroutine        @2.3
            exec_sys rm -rf   ${mcdir[cxt]}
            exec_sys mkdir -p ${mcdir[cxt]}
            exec_sys mv -f    ${intermediate}_mc.par \
                              ${rps[cxt]}
            exec_sys mv -f    ${intermediate}_mc_abs_mean.rms \
                              ${abs_mean_rms[cxt]}
            exec_sys mv -f    ${intermediate}_mc_abs.rms \
                              ${abs_rms[cxt]}
            exec_sys mv -f    ${intermediate}_mc_rel_mean.rms \
                              ${rel_mean_rms[cxt]}
            exec_sys rm -f    ${relrms[cxt]}
            exec_sys echo     0                     >> ${rel_rms[cxt]}
            exec_sys cat ${intermediate}_mc_rel.rms >> ${rel_rms[cxt]}
            #######################################################
            # Compute the maximum value of motion.
            #######################################################
            subroutine        @2.4
            exec_xcp 1dTool.R \
               -i    ${rel_rms[cxt]} \
               -o    max \
               -f    ${rel_max_rms[cxt]}
            #######################################################
            # Generate summary plots for motion correction.
            #######################################################
            subroutine        @2.5  [Preparing summary plots]
            subroutine      @2.5.1  [1/3]
            exec_fsl fsl_tsplot -i ${rps[cxt]} \
               -t 'MCFLIRT_estimated_rotations_(radians)' \
               -u 1 --start=1 --finish=3 \
               -a x,y,z \
               -w 640 \
               -h 144 \
               -o ${mcdir[cxt]}/rot.png
            subroutine      @2.5.2  [2/3]
            exec_fsl fsl_tsplot -i ${rps[cxt]} \
               -t 'MCFLIRT_estimated_translations_(mm)' \
               -u 1 --start=4 --finish=6 \
               -a x,y,z \
               -w 640 \
               -h 144 \
               -o ${mcdir[cxt]}/trans.png
            subroutine      @2.5.3  [3/3]
            exec_fsl fsl_tsplot \
               -i "${abs_rms[cxt]},${rel_rms[cxt]}" \
               -t 'MCFLIRT_estimated_mean_displacement_(mm)' \
               -u 1 \
               -w 640 \
               -h 144 \
               -a 'absolute,relative' \
               -o ${mcdir[cxt]}/disp.png
            #######################################################
            # Compute framewise quality metrics.
            #######################################################
          #  temporal_mask  --SIGNPOST=${signpost}        \
                           #--INPUT=${intermediate}_mc    \
                          # --RPS=${rps[cxt]}             \
                          # --RMS=${rel_rms[cxt]}         \
                          # --THRESH=${prestats_framewise[cxt]}
         fi # run check statement
         ##########################################################
         # * Remove the motion corrected image: this step should
         #   only compute parameters, not use them.
         # * Discard realignment transforms, since they are not
         #   used in this step.
         # * Symlink to the previous image in the chain so that
         #   the final check can verify that this step completed
         #   successfully.
         # * Update the image pointer.
         ##########################################################
         exec_sys rm -f  ${intermediate}_${cur}.nii.gz
         exec_sys rm -rf ${intermediate}_mc*.mat
         exec_sys ln -sf ${intermediate}.nii.gz ${intermediate}_${cur}.nii.gz
         intermediate=${intermediate}_${cur}
         routine_end
         ;;
      
      
      
      
      
      MCO)
         ##########################################################
         # MCO computes the realignment parameters and uses them
         # to realign all volumes to the reference.
         #
         # MPR is intended to be run prior to slice timing
         # correction, and MCO after slice timing correction.
         ##########################################################
         routine              @3    Realigning functional volumes
         if ! is_image ${referenceVolume[cxt]} \
         || rerun
            then
            subroutine        @3.1  [Extracting reference volume]
            nvol=$(exec_fsl fslnvols ${intermediate}.nii.gz)
            #######################################################
            # If the framewise displacement has not been
            # calculated, then use the timeseries midpoint as the
            # reference volume.
            #######################################################
            if ! is_1D ${fd[cxt]}
               then
               subroutine     @3.2
               midpt=$(( ${nvol} / 2 ))
               exec_fsl \
                  fslroi ${intermediate}.nii.gz \
                  ${referenceVolume[cxt]} \
                  ${midpt} 1
            #######################################################
            # Otherwise, use the volume with minimal framewise
            # displacement.
            #######################################################
            else
               subroutine     @3.3
               vol_min_fd=$(exec_xcp \
                  1dTool.R -i ${fd[cxt]} -o which_min -r T)
               exec_fsl \
                  fslroi ${intermediate}.nii.gz \
                  ${referenceVolume[cxt]} \
                  ${vol_min_fd} 1
            fi
         fi
         ##########################################################
         # Create the motion correction directory if it does not
         # already exist.
         ##########################################################
         exec_sys mkdir -p ${mcdir[cxt]}
         exec_sys mkdir -p ${rmat[cxt]}
         ##########################################################
         # Verify that this step has not already completed; if it
         # has, then an associated image should exist.
         ##########################################################
         if ! is_image ${intermediate}_${cur}.nii.gz \
         || rerun
            then
            subroutine        @3.4  [Executing motion realignment]
            proc_fsl    ${intermediate}_mc.nii.gz  \
               mcflirt -in ${intermediate}.nii.gz  \
               -out     ${intermediate}_mc         \
               -reffile ${referenceVolume[cxt]}    \
               -mats             -spline_final
         fi
         ##########################################################
         # Realignment transforms are always retained from this
         # step and discarded from MPR.
         ##########################################################
         [[ -e ${intermediate}_mc*.mat ]] && exec_sys \
            mv -f ${intermediate}_mc*.mat \
            ${rmat[cxt]}
         ##########################################################
         # Update image pointer
         ##########################################################
         exec_fsl immv ${intermediate}_mc.nii.gz ${intermediate}_${cur}.nii.gz
         intermediate=${intermediate}_${cur}
         routine_end
         ;;
      
      
      
      
      
      STM)
         ##########################################################
         # STM corrects images for timing of slice acquisition
         # based upon user input.
         ##########################################################
         routine              @4    Slice timing correction
         subroutine           @4.1a Acquisition: ${prestats_stime[cxt]}
         subroutine           @4.1b Acquisition axis: ${prestats_sdir[cxt]}
         if ! is_image ${intermediate}_${cur}.nii.gz \
         || rerun
            then
            st_perform=1
            #######################################################
            # Read in the acquisition axis; translate axes from
            # common names to FSL terminology.
            #######################################################
            case "${prestats_sdir[cxt]}" in 
            X)
               subroutine     @4.2a
               sdir=1
               ;;
            Y)
               subroutine     @4.2b
               sdir=2
               ;;
            Z)
               subroutine     @4.2c
               sdir=3
               ;;
            *)
               sdir=3 # set default so as to prevent errors
               subroutine     @4.2d Slice timing correction:
               subroutine     @4.2e Unrecognised acquisition axis/direction:
               subroutine     @4.2f ${prestats_sdir[cxt]}
               ;;
            esac
            #######################################################
            # Read in the direction of acquisition to determine
            # the order in which slices were acquired.
            #######################################################
            unset st_arguments
            case "${prestats_stime[cxt]}" in
            up)
               subroutine     @4.3
               ;;
            down)
               subroutine     @4.4
               st_arguments='--down'
               ;;
            interleaved)
               subroutine     @4.5
               st_arguments='--odd'
               ;;
            custom)
               subroutine     @4.6
               st_custom_time=${prestats_stime_tpath[cxt]}
               st_custom_order=${prestats_stime_opath[cxt]}
               ####################################################
               # If you are using both a custom order file and a
               # custom timing file, then congratulations -- you've
               # broken the pipeline. Just select one.
               #
               # The call is still here, but should it become
               # active, the very fabric of the world will unravel.
               ####################################################
               if [[ "${prestats_stime_order[cxt]}" == "true" ]]
                  then
                  subroutine  @4.6.1
                  st_arguments="${st_arguments} -ocustom ${st_custom_order}"
               fi
               if [[ "${prestats_stime_timing[cxt]}" == "true" ]]
                  then
                  subroutine  @4.6.2
                  st_arguments="${st_arguments} -tcustom ${st_custom_time}"
               fi
               ;;
            none)
               st_perform=0
               ;;
            *)
               subroutine     @4.7  Unrecognised option ${prestats_stime[cxt]}
               st_perform=0
               ;;
            esac
            if (( ${st_perform} == 1 ))
               then
               subroutine     @4.8
               exec_fsl \
                  slicetimer \
                  -i ${intermediate}.nii.gz \
                  -o ${intermediate}_${cur}.nii.gz \
                  -d $st_direction \
                  ${st_arguments}
            else
               subroutine     @4.9
               exec_sys ln -sf ${intermediate}.nii.gz ${intermediate}_${cur}.nii.gz
            fi
         fi # run check statement
         intermediate=${intermediate}_${cur}
         to_reorient=${intermediate}.nii.gz
         import_image   to_reorient ${intermediate}.nii.gz  --ORIENT=1
         routine_end
         ;;
      
      
      
      
      
      BXT)
         ##########################################################
         # BXT computes a mask over the whole brain and excludes
         # non-brain voxels from further analyses.
         ##########################################################
         routine              @5    Brain extraction
         subroutine           @5.1  [Generating mean functional image]
         ##########################################################
         # Generate a mean functional image by averaging voxel
         # intensity over time. This mean functional image will be
         # used as the primary reference for establishing the
         # boundary between brain and background.
         ##########################################################
         exec_fsl fslmaths ${intermediate}.nii.gz -Tmean ${meanIntensity[cxt]}
         if ! is_image ${intermediate}_${cur}_1.nii.gz \
         || rerun
            then
            subroutine        @5.2a [Initialising brain extraction]
            subroutine        @5.2b [Fractional intensity threshold:]
            subroutine        @5.2c [${prestats_fit[cxt]}]
            #######################################################
            # Use BET to generate a preliminary mask. This should
            # be written out to the mask[cxt] variable.
            #######################################################
            exec_fsl \
               bet ${meanIntensity[cxt]} \
               ${outdir}/${prefix} \
               -f ${prestats_fit[cxt]} \
               -n \
               -m \
               -R
            exec_fsl immv ${outdir}/${prefix}.nii.gz ${meanIntensityBrain[cxt]}
            #######################################################
            # Additionally, prepare a brain-extracted version of
            # the example functional image; this will later be
            # necessary for coregistration of functional and
            # structural acquisitions.
            #######################################################
            if is_image ${referenceVolume[sub]}
               then
               subroutine     @5.3a
               exec_fsl bet ${referenceVolume[sub]} \
                  ${referenceVolumeBrain[cxt]}      \
                  -f ${prestats_fit[cxt]}
            else
               subroutine     @5.3b
               exec_fsl bet ${referenceVolume[cxt]} \
                  ${referenceVolumeBrain[cxt]}      \
                  -f ${prestats_fit[cxt]}
            fi
            subroutine        @5.4  [Initial estimate]
            #######################################################
            # Use the preliminary mask to extract brain tissue.
            #######################################################
            exec_fsl \
               fslmaths ${intermediate}.nii.gz \
               -mas ${mask[cxt]} \
               ${intermediate}_${cur}_1.nii.gz
         fi
         if ! is_image ${intermediate}_${cur}_2 \
         || rerun
            then
            subroutine        @5.5a [Thresholding and dilating image]
            subroutine        @5.5b [Brain-background threshold:]
            subroutine        @5.5c [${prestats_bbgthr[cxt]}]
            #######################################################
            # Use the user-specified brain-background threshold
            # to determine what parts of the image to count as
            # brain.
            #  * First, compute an image-specific threshold by
            #    multiplying the 98th percentile of image
            #    intensities by the brain-background threshold.
            #  * Next, use this image-specific threshold to obtain
            #    a binary mask from the volume computed in the
            #    first pass.
            #  * Then, dilate the binary mask.
            #  * Finally, use the new, dilated mask for the second
            #    pass of brain extraction.
            #######################################################
            perc_98=$(exec_fsl fslstats ${intermediate}.nii.gz -p 98)
            new_thresh=$(arithmetic ${perc_98}\*${prestats_bbgthr[cxt]})
            exec_fsl fslmaths ${intermediate}_${cur}_1.nii.gz \
               -thr  ${new_thresh}  \
               -Tmin                \
               -bin                 \
               ${mask[cxt]}         \
               -odt char
            subroutine        @5.6
            exec_fsl fslmaths ${mask[cxt]} -dilF ${mask[cxt]}
            proc_fsl    ${intermediate}_${cur}.nii.gz \
               fslmaths ${intermediate}.nii.gz        \
               -mas     ${mask[cxt]}                  \
               %OUTPUT
         fi
         intermediate=${intermediate}_${cur}
         routine_end
         ;;
      
      
    
      
      DMT)
         ##########################################################
         # DMT removes the mean from a timeseries and additionally
         # removes polynomial trends up to an order specified by
         # the user.
         #
         # DMT uses a general linear model with y = 1 and all
         # polynomials as predictor variables, then retains the
         # residuals of the model as the processed timeseries.
         ##########################################################
         routine              @6    Demeaning and detrending BOLD timeseries
         demean_detrend       --SIGNPOST=${signpost}           \
                              --ORDER=${prestats_dmdt[cxt]}    \
                              --INPUT=${intermediate}          \
                              --OUTPUT=${intermediate}_${cur}  \
                              --1DDT=${prestats_1ddt[cxt]}     \
                              --CONFIN=${confproc[cxt]}        \
                              --CONFOUT=${intermediate}_${cur}_confmat.1D
         intermediate=${intermediate}_${cur}
         configure            confproc  ${intermediate}_confmat.1D
         routine_end
         ;;
      
      
      
      
      
      DSP)
         ##########################################################
         # DSP uses AFNI's 3dDespike to remove any intensity
         # outliers ("spikes") from the BOLD timeseries and to
         # interpolate over outlier epochs.
         ##########################################################
         routine              @7    Despiking BOLD timeseries
         remove_outliers      --SIGNPOST=${signpost}           \
                              --INPUT=${intermediate}          \
                              --OUTPUT=${intermediate}_${cur}  \
                              --CONFIN=${confproc[cxt]}        \
                              --CONFIN=${intermediate}_${cur}_confmat.1D
         intermediate=${intermediate}_${cur}
         configure            confproc  ${intermediate}_confmat.1D
         routine_end
         ;;
      
      
      
      
      
      SPT)
         ##########################################################
         # SPT applies a smoothing kernel to the image. It calls
         # the utility script sfilter, which is also used by a
         # number of other modules.
         ##########################################################
         routine              @8    Spatially filtering image
         smooth_spatial       --SIGNPOST=${signpost}           \
                              --FILTER=prestats_sptf[$cxt]     \
                              --INPUT=${intermediate}          \
                              --USAN=${prestats_usan[cxt]}     \
                              --USPACE=${prestats_usan_space[cxt]}
         smoothed='img_sm'${prestats_smo[cxt]}'['${cxt}']'
         intermediate=${intermediate}_${cur}
         proc_fsl ${intermediate}.nii.gz immv ${!smoothed} %OUTPUT
         routine_end
         ;;
      
      
      
      
      
      TMP)
         ##########################################################
         # TMP applies a temporal filter to:
         #  * the 4D BOLD timeseries
         #  * any derivative images that have the same number of
         #    volumes as the 4D timeseries
         #  * any 1D timeseries that might function as potential
         #    regressors: for instance, realignment parameters
         # TMP makes use of the utility function tfilter, which
         # itself calls fslmaths, 3dBandpass, or the R script
         # genfilter to enable a wide array of filters.
         ##########################################################
         routine              @9    Temporally filtering image
         filter_temporal      --SIGNPOST=${signpost}              \
                              --FILTER=${prestats_tmpf[cxt]}      \
                              --INPUT=${intermediate}             \
                              --OUTPUT=${intermediate}_${cur}     \
                              --CONFIN=${confproc[cxt]}           \
                              --CONFOUT=${intermediate}_${cur}_confmat.1D \
                              --HIPASS=${prestats_hipass[cxt]}    \
                              --LOPASS=${prestats_lopass[cxt]}    \
                              --ORDER=${prestats_tmpf_order[cxt]} \
                              --DIRECTIONS=${prestats_tmpf_pass[cxt]} \
                              --RIPPLE_PASS=${prestats_tmpf_ripple[cxt]} \
                              --RIPPLE_STOP=${prestats_tmpf_ripple2[cxt]}
         intermediate=${intermediate}_${cur}
         configure            confproc  ${intermediate}_confmat.1D
         routine_end
         ;;




      REF)
         ##########################################################
         # REF assumes that the data have already been minimally
         # preprocessed and uses them to generate a reference
         # volume, a mean image, and a brain mask so that these
         # can be used by downstream modules.
         ##########################################################
         routine              @10   Importing references
         subroutine           @10.0 [Assuming data are already processed]
         subroutine           @10.1 [Selecting reference volume]
         
         nvol=$(exec_fsl fslnvols ${intermediate}.nii.gz)
         midpt=$(( ${nvol} / 2))
         proc_fsl ${referenceVolume[cxt]} \
            fslroi                  \
            ${intermediate}.nii.gz  \
            %OUTPUT                 \
            ${midpt} 1
         subroutine           @10.2 [Computing mean volume]
         proc_fsl ${meanIntensity[cxt]} \
                  fslmaths ${intermediate}.nii.gz  -Tmean   %OUTPUT
         if is_image ${mask[sub]}
            then
            subroutine        @10.3 [Computing mask]
            proc_fsl ${mask[cxt]} \
                     fslmaths ${meanIntensity[cxt]} -bin    %OUTPUT
            exec_sys rln   ${referenceVolume[cxt]} \
                           ${referenceVolumeBrain[cxt]}
            exec_sys rln   ${meanIntensity[cxt]}   \
                           ${meanIntensityBrain[cxt]}
         else
          
            subroutine        @10.4 Importing mask
            exec_fsl fslmaths ${referenceVolume[cxt]} \
               -mul  ${mask[cxt]} \
               ${referenceVolumeBrain[cxt]}
            exec_fsl fslmaths ${meanIntensity[cxt]} \
               -mul  ${mask[cxt]} \
               ${meanIntensityBrain[cxt]}
        
         fi
         subroutine           @10.5 Defining spatial reference
         space_set      ${spaces[sub]}   ${space[sub]} \
              Map       ${meanIntensityBrain[cxt]}
         subroutine           @10.6 [Adding link references]
         exec_sys rln   ${intermediate}.nii.gz  \
                        ${intermediate}_${cur}.nii.gz
         intermediate=${intermediate}_${cur}
         routine_end
         ;;
      
      
      
      
      
      *)
         subroutine           @E.1     Invalid option detected: ${cur}
         ;;
         
   esac
done


###################################################################
# CLEANUP
#  * Test for the expected output. This should be the initial
#    image name with any routine suffixes appended.
#  * If the expected output is present, move it to the target path.
#  * If the expected output is absent, notify the user.
###################################################################
apply_exec        timeseries              ${prefix}_%NAME \
   fsl            imcp %INPUT %OUTPUT
if is_image ${intermediate_root}${buffer}.nii.gz
   then
   subroutine                 @0.2
   processed=$(readlink -f    ${intermediate}.nii.gz)
   exec_fsl imcp ${processed} ${preprocessed[cxt]}
   trep=$(exec_fsl fslval ${img[sub]} pixdim4)
   exec_xcp addTR.py -i ${preprocessed[cxt]} -o ${preprocessed[cxt]} -t ${trep} 
   exec_afni 3dresample -orient ${template_orientation} \
              -inset ${preprocessed[cxt]} \
              -prefix ${preprocessed[cxt]} -overwrite 
  fslmaths ${preprocessed[cxt]}  -mul 1 ${preprocessed[cxt]}
   
   completion
else
   subroutine                 @0.3
   abort_stream \
"Expected output not present.]
[Expected: ${buffer}]
[Check the log to verify that processing]
[completed as intended."
fi
