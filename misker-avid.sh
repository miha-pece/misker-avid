#!/bin/bash

# This is BASH wrapper for ffmpeg with primary function of muxing
# AVID media files (Avid Technology, Inc.). It works in batch mode,
# so it will analyze and then mux (or transcode) all files
# stored in defined folder.

# Made by Miha Peče, ZRC-SAZU

set -o nounset

#################################################################
####                 Declarations                            ####
#################################################################

declare -a main_list
declare -a sort_list

declare PROCESSING=true # If false: only names of files in folder will be sorted,
					    # modified and printed on the screen. 
declare MUXING=false  # Muxing=true: program will mux streams  
   					 # Muxing=false: program will transcode streams
declare SHORT_TRANSFORM=true  # Option for test-transform. If true,
                               # only short amount of video will be transformed

declare NUM_STREAMS=3 #Number of connected streams, most common value is 3 (1v,2A)
declare IN_FOLDER="/Volumes/My Book/Avid MediaFiles LaCie 2/MXF/tmp/"
				  # Input folder with path
declare OUT_FOLDER="/Volumes/VIDEO_R0/TMP/" # Output folder with path

declare FFMPEG_LOG_FILE=true # Separate ffmpeg output into log file. 
							 # If false, it will be printed on the screen
declare EXE_DIR="$PWD" # Log file will be the stored in same folder as script 

declare ALL_TIME



#################################################################
####               Basic verifications                       ####
#################################################################

# Chenge to folder where media files are stored
cd "$IN_FOLDER"

# Checking if action succeeded
if [ $? -ne 0 ]; then
	tput setaf 1
	echo
	echo "  #############################################"
	echo "  #  Something went wrong changing directory  #"
	echo "  #############################################"
	tput sgr0
	exit 1
fi

if [ ! -d "$OUT_FOLDER" ]; then
	
	mkdir -p "$OUT_FOLDER"
	
	# Checking if action succeeded
	if [ $? -ne 0 ]; then
		tput setaf 1
		echo
		echo "  #############################################"
		echo "  #      Something went wrong with mkdir      #"
		echo "  #############################################"
		tput sgr0
		exit 1
	fi
fi

# Checking if ffmpeg is installed
ffmpeg -h &> /dev/null

if [ $? -eq 0 ]; then
	echo
  	echo "  ####################"
	echo "  # ffmpeg installed #"
	echo "  ####################"
else
	tput setaf 1
	echo ""
	echo "  ########################"
	echo "  # ffmpeg seems missing #"
	echo "  ########################"
	tput sgr0
	echo
	exit 1
fi



#################################################################
####                     Function                            ####
#################################################################

# Muxing/transcoding function
function transform_files {
	
	local counter=0
	local -a tmp_ffmpeg=("ffmpeg")
	local -a list_ffmpeg
	local -a tmp_list=()
	local START_TIME=$(date +%s)
	
	for x in "${sort_list[@]}"; do
		
		# Delimiting segments of name and writing them in variables
		id=$(echo "$x" | awk -F'@' '{ print $1 }')
		tape=$(echo "$x" | awk -F'@' '{ print $2 }')
		mod_date=$(echo "$x" | awk -F'@' '{ print $3 }')
		file=$(echo "$x" | awk -F'@' '{ print $4 }')
		
		# Repeating process $NUM_STREAMS times
		if [ $counter -lt $NUM_STREAMS ]; then
			tmp_list+=("$file")
			counter=$(( $counter + 1 ))
		fi
		
		# Writing the whole ffmpeg command in array when
		# process was repeated $NUM_STREAMS times
		if [ $counter -eq $NUM_STREAMS ]; then
			
			# Defining outfile with PATH and replacing spaces, : with _
			if [ $MUXING == true ]; then
				out_file="\"${OUT_FOLDER}${id}.${tape}.${mod_date}.output.mxf\""
			else
				out_file="\"${OUT_FOLDER}${id}.${tape}.${mod_date}.output.mp4\""
			fi
			out_file=$(echo "$out_file" | sed -e 's/ /_/g' -e 's/:/-/g')
			
			# Adding to ffmpeg command: input files with flags
			for ((i=0;i<${NUM_STREAMS};++i)); do
				tmp_ffmpeg+=("-i \"${tmp_list[$i]}\"") 
			done
			
			# If $SHORT_TRANSFORM true, only t=duration of video will be transformed
			# Transformation will start at ss=second
			if [ $SHORT_TRANSFORM == true ]; then
				tmp_ffmpeg+=("-ss 20 -t 10")
			fi
			
			# Different options for muxing/transcoding
			if [ $MUXING == true ]; then
				# Just muxing all streams
				tmp_ffmpeg+=("-vcodec copy -acodec copy -y" "${out_file}")
			else
				# Transcoding in h264
				# Deinterlacing and forcing aspect because ffmpeg cant read AVID stream aspect
				# Caution: change acording particular source and need: https://ffmpeg.org/ffmpeg.html
				tmp_ffmpeg+=("-vf yadif=0:-1:0,setdar=dar=16/9")
				tmp_ffmpeg+=("-c:v libx264 -pix_fmt yuv420p -preset ultrafast -crf 20")
				tmp_ffmpeg+=("-c:a aac -strict experimental -b:a 128k -ar 48000 -y" "${out_file}")
			fi
			
			# Combining all arguments in one string and storing it
			# into another array
			list_ffmpeg+=("${tmp_ffmpeg[*]}")
			
			# Reseting variables for next iteration
			tmp_ffmpeg=("ffmpeg")
			tmp_list=()
			counter=0
		fi	
	done
	
	echo
	echo "Executing ..."
	echo
	
	# Touching and clearing log file
	if [ $FFMPEG_LOG_FILE == true ]; then
		touch "${EXE_DIR}/misker_avid.log"
		: > "${EXE_DIR}/misker_avid.log"
	fi
	
	# Executing stored ffmpeg commands
	for ff_command in "${list_ffmpeg[@]}"; do
		
		echo "$ff_command"
		echo
		
		# Executing with log file or screen output
		if [ $FFMPEG_LOG_FILE == true ]; then
			eval "$ff_command >> ${EXE_DIR}/misker_avid.log 2>&1"
		else
			eval "$ff_command"
		fi
		
		if [ $? -ne 0 ]; then
			tput setaf 1
			echo
			echo "  #############################################"
			echo "  #  Something went wrong muxing/encoding     #"
			echo "  #############################################"
			tput sgr0
			echo
			exit 1
		else
			tput setaf 2
			echo 
			echo "  ##############################"
			echo "  #  Muxing/encoding finished  #"
			echo "  ##############################"
			tput sgr0
			echo
		fi
	done
	
	ALL_TIME=$(date +%s)
	ALL_TIME=$(( $ALL_TIME - $START_TIME ))
}



#################################################################
####     Main: loop folder, cunstructing name,               ####
####           sorting, calling function                     ####
#################################################################

for selec_file in *; do
	
	# Conditions while looping in source folder
	
	# If folder, load next element
	if [ -d "$selec_file" ]; then
		continue
	fi
	
	filename=$(basename "$selec_file")
	extension="${filename##*.}"
		
	# If not mxf extension, load next element
	if [ "$extension" != "mxf" ]; then
	  	continue
	fi

	# If empty file, break
	if [ ! -s "$selec_file" ]; then
	  	echo "  ${selec_file} has 0 bits"
	    exit 1
	fi

	# Extracting metadata for name
	# Extract common ID from name, delimiter is set as @
	tmp_data=$(echo "$selec_file" | awk -F'.' '{ print $2 }') 
	tmp_data+="@"
	
	# Extract Reel/tape name from ffmpeg metadata output
	tmp_data+=$(ffmpeg -i "${selec_file[0]}" 2>&1 | awk -F':' '/reel_name/ { print $2 }')
	tmp_data+="@"
	
	# Extract Modification date from ffmpeg output
	tmp_data+=$(ffmpeg -i "${selec_file[0]}" 2>&1 | awk -F' ' '/modification_date/ { print $2, $3 }')

	# Append file name, delimiter is again @
	tmp_data+="@$selec_file" 
	main_list+=("$tmp_data")
	
done

OLDIFS=$IFS
IFS=$'\n'

# Sorting files in list
sort_list=($(sort <<<"${main_list[*]}"))

# Printing sorted list
echo
echo "Files to transform: "
echo

for x in "${sort_list[@]}"; do
	echo "$x"
done

IFS=$OLDIFS

# Simple check
num_files=${#sort_list[@]}

if [ $(( $num_files % $NUM_STREAMS )) -eq 0 ]; then
	echo
	echo "There are ${num_files} files to transform."
	echo "Final number of output files will be $(( num_files / $NUM_STREAMS ))."
else
	tput setaf 1
	echo
	echo "There are ${num_files}to mux,"
	echo "and you cann\47t divide them with $NUM_STREAMS."
	tput sgr0
	echo
	exit 1
fi

# Calling main function
if [ "$PROCESSING" == true ]; then
	
	transform_files
	
	# Post-process information
	echo -n "Number of files in output folder: "
	ls "$OUT_FOLDER" | wc -l
	
	echo -n "Finished: "
	date
	
	echo -n "Duration of process: "
	printf "%02d:" $(( $ALL_TIME / 3600 ))
	printf "%02d:" $(( ($ALL_TIME % 3600) / 60 ))
	printf "%02d\n" $(( $ALL_TIME % 60 ))
	
else
	echo
	echo "Just readind input folder and sorting files."
	echo
fi

