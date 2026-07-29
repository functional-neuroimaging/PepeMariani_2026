#!/bin/bash

# This Script performs the processing of fUSI data slice wise. It applies successively the following steps to remove nuisances:
#
# 1- Despikes the ts. 
#
# https://www.sciencedirect.com/science/article/pii/S1053811914001578#f0090
#
# 2- Performs the regression over a list of regressors
#
# 3- Filters between [0.01, 0.1] Hz
#
# 4- Smooth data with a 300mu kernel
#
# BE CAREFUL due to ANTs implementation this script will use all resources of your WS
#
# -----------------------------------------------------------
#
# Script inspired by Marco Pagani's edited by JC Mariani
# Functional Neuroimaging Lab, 
# Istituto Italiano di Tecnologia, Rovereto
# (2023)
# -----------------------------------------------------------


# -----------------------------------------------------------
# Function to process
# -----------------------------------------------------------

############################## Initialise for multiple regressors

#regressors="regressor-FirstMode regressor-GlobalSignal regressor-lowIntensitySignal regressor-tCompCorN1P100 regressor-tCompCorN1P2 regressor-tCompCorN5P2 regressor-WMCSFsignal regressor-aCompCor regressor-NoReg regressor-outPC5"

# regressors="regressor-aCompCor regressor-NoReg regressor-outPC5"
regressors="regressor-aCompCor"

# Declare a string array with type
# declare -a regressor_idxs=("1" "1" "1" "1" "1" "1,2,3,4,5" "1" "1,2,3,4,5" "1" "1,2,3,4,5")
# declare -a regressor_idxs=("1,2,3,4,5" "1" "1,2,3,4,5")
declare -a regressor_idxs=("1,2,3,4,5")

touch temp_regressors_name.txt
touch temp_regressor_idxs.txt

for regressorName in $regressors
do
	echo $regressorName >> temp_regressors_name.txt
done

for regressor_idx in ${regressor_idxs[@]}
do
	echo $regressor_idx >> temp_regressor_idxs.txt
done

############################## Defines the functions


function despike_subject {

    ts=$1
    subject=$(basename $ts _pwd.nii.gz)
    
    3dDespike \
        -nomask \
        -prefix ${subject}Despiked_pwd.nii.gz \
        $ts \
        &> ${subject}_log_despiking.txt	
	
}
export -f despike_subject

# -----------------------------------------------------------
# Function to regress
# -----------------------------------------------------------

function regress_nuisance_subject {

    ts=$1
    suffix=$2
    regressor_col=$3
    subject=$(basename $ts Despiked_pwd.nii.gz) # registered ts
    #mcp=${subject}_mcf.txt # motion traces

   echo $subject     

    Text2Vest ${subject}_${suffix}.txt ${subject}_to_regress.mat

    # nuisance regression. 
    fsl_regfilt \
	-i $ts \
	-d ${subject}_to_regress.mat \
	-f ${regressor_col} \
        -o ${subject}REG${suffix}_pwd.nii.gz 

    # rm ${subject}_to_regress.mat
       
    }
export -f regress_nuisance_subject

# -----------------------------------------------------------
# Function to bandpass
# -----------------------------------------------------------

function bandpass_filter {

    ts=$1
    subject=$(basename $ts _pwd.nii.gz) 
    
    tr=2.4 # edit this
    bandpass_from=0.01 # edit this to change filter lower limit
    bandpass_to=0.1 # edit this to change filter upper limit
    
    # gets the position index
    
    tmp=${ts#*pose-}   
    poseIndex=${tmp%_proc-chopped*}
    
    brainmask=/media/DATA2/JC/1_DATA/2025-02-24_PepeMariani/derivatives/01_SWregistration/derivatives/Params/pose_templates/*AllenMask*pose-${poseIndex}*.nii.gz # edit this
    
    echo $ts
    echo $subject    
    echo $brainmask

    # this filters ts
    3dBandpass \
        -dt $tr \
        -mask $brainmask \
        -prefix ${subject}Filtered_pwd.nii.gz \
        ${bandpass_from} ${bandpass_to} \
        ${ts}

}
export -f bandpass_filter

# -----------------------------------------------------------
# Function to smooth
# -----------------------------------------------------------

function smooth {

    ts=$1
    subject=$(basename $ts _pwd.nii.gz)
    
    kernel=0.3
    
    # gets the position index
    
    tmp=${ts#*pose-}   
    poseIndex=${tmp%_proc-chopped*}
    
    brainmask=/media/DATA2/JC/1_DATA/2025-02-24_PepeMariani/derivatives/01_SWregistration/derivatives/Params/pose_templates/*AllenMask*pose-${poseIndex}*.nii.gz # edit this

     3dBlurInMask \
        -input $ts \
        -prefix ${subject}Smoothed_pwd.nii.gz \
        -mask $brainmask \
        -FWHMxyz  $kernel $kernel 0.
        
        
    }
export -f smooth

# -----------------------------------------------------------
# function calls
# -----------------------------------------------------------

############################## Loop

numjobs=20

# main code starts here

# despike
echo sub*registered_pwd.nii.gz | tr " " "\n" > subject_list_despike.txt
parallel \
    -j $numjobs \
    despike_subject {} \
    < subject_list_despike.txt
    
# regress
echo sub*Despiked_pwd.nii.gz | tr " " "\n" > subject_list_regress.txt # edit this, registered ts

#for regressorName in $regressors
paste temp_regressors_name.txt temp_regressor_idxs.txt | while read regressorName regressor_idx
do
	
	echo AAAAAAAAAAAAAAAAAAAAAAAAAAAAA-${regressorName} - ${regressor_idx}-AAAAAAAAAAAAAAAAAAAAAAAAAAAAA
	
	parallel \
	    -j $numjobs \
	    regress_nuisance_subject {} $regressorName ${regressor_idx}\
	    < subject_list_regress.txt
	    
	# filter
	echo sub*registeredREG${regressorName}_pwd.nii.gz | tr " " "\n" > subject_list_filter.txt #

	parallel \
	    -j $numjobs \
	    bandpass_filter {} \
	    < subject_list_filter.txt

	# smooth
	echo sub*registeredREG${regressorName}Filtered_pwd.nii.gz | tr " " "\n" > subject_list_smooth.txt

	parallel \
	    -j $numjobs \
	    smooth {} $kernel $brainmask \
	    < subject_list_smooth.txt
	    
done

rm temp_regressors_name.txt
rm temp_regressor_idxs.txt




    

