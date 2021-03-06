#! /bin/bash

usage="usage: $0 [<options>] <list>

Check if jobs were completed and repair if needed where <list> is
the file with the list of fitted points in the sensitivity folder.
Works with HTCondor or Slurm.

Options
    -f	      repair files, otherwise just display information
    -i	      if trisens.sh is running, just ignore it
    -w <dir>  if the log files are in a different directory,
              please specify it
    -h        print this message
"

rep=false
skip=false
logr=""
root=""
while getopts 'i:r:w:fh' flag; do
	case "${flag}" in
		f) rep=true ;;
		i) skip=true ;;
		r) root="${OPTARG}" ;;
		w) logr="${OPTARG}" ;;
		h) echo "$usage" >&2
		   exit 0 ;;
		*) printf "illegal option -%s\n" "$OPTARG" >&2
		   echo "$usage" >&2
		   exit 1 ;;
	esac
done
pointfile=$root
echo "logr is "$logr

shift $((OPTIND-1))

if [ "$#" -ne 1 ] ; then
	echo This script requires one argument. Check usage with
	echo -e "\n    $0 -h\n"
	#exit 1
elif [ ! -s "$1" ] ; then
	echo Argument \"$1\" is not valid. Check usage with
	echo -e "\n    $0 -h\n"
	exit 1
fi

Sens=$PWD/bin/fitter
nameExec=fitter
trisens=trisens.sh


if [ "$skip" == "false" ] && pgrep $trisens ; then
	echo trisens.sh is still running. Wait for it to finish.
	exit 1
fi


SCHED=""
queue=".queue_status"
if condor_q &> /dev/null ; then
	SCHED="HTCONDOR"
	sub=condor_submit
	condor_q -autoformat cmd args > $queue
elif squeue &> /dev/null ; then
	SCHED="SLURM"
	sub=sbatch
	squeue -h -r -u $USER -o "%o %K" > $queue
else
	echo There is neither HTCondor nor Slurm on this machine. I am sorry, I cannot help you
	exit 1
fi

name=${root%.*}
name_log=$logr
root=${name%/*}
echo "name is "$name
if [[ "$root" != /* ]] ; then
	root=$PWD/${root%/}
else
	root=${root%/}
fi

repeat=()
while read -r point ; do
	# if finished is not shown, means something bad happened
	echo Checking point $point

	outdir=$name'_'$point
	outdir=$(realpath $outdir)
	script=$(ls -rt $outdir/R*.$point.sub | tail -n1)

	outlog=$name_log'_'$point
	outlog=$(realpath $outlog)
	
	# directory does not exists or no script
	if ! [ -d "$outdir" ] || ! [ -s "$script" ] ; then
		echo Detected: directory $outdir or $script do not exist
		if [ "$rep" == "true" ] ; then
			echo Point $point will be resubmitted
			repeat=(${repeat[@]} $point)
		else
			echo Point $point is missing. You can resubmit with -f to repair
		fi
		continue
	fi

	# find all root files
	all=$(find $outdir -name "SpaghettiSens.*.root")
	all=(${all})

	if [ "${#all[@]}" -eq 0 ] ; then # no files
		# check if job is still running
		echo Detected: there are no output files in $outdir
		if grep -q $point $queue; then 
			echo $nameExec for point $point is still running. Just wait.
		elif [ "$rep" == "true" ] ; then
			echo Point $point will be resubmitted
			repeat=(${repeat[@]} $point)
		else
			echo $nameExec for point $point failed and never ran. You can resubmit with -f to repair
		fi
		continue
	fi 


	# find how many jobs there should be
	if grep -q queue $script ; then
		job=$(grep queue $script | cut -f2 -d' ')
	elif grep -q array $script ; then
		job=$(grep array $script | cut -f4 -d'-')
		job=$((job + 1))	# arrays start from 0
	fi

	# now all known files
	for out in "${all[@]}" ; do

		# skip file with weird format
		if ! [[ "$out" =~ SpaghettiSens\.[0-9]+\.root ]] ; then
			echo Detected: skip unknown file $out
			continue
		fi

		num=${out%.root}
		num=${num##*.}

		if [ "$num" -ge "$job" ] ; then
			echo Detected: file misplaced $out 
			if [ "$rep" == "true" ] ; then
				rm $out
			else
				echo "    " you can resubmit with -f to delete
			fi
			continue
		fi
	done

	repair=()
	for num in $(seq $((job - 1)) ) ; do 

		out=$outdir/SpaghettiSens.$num.root
		log=$outlog/L$nameExec.$num.log
		bad=false
		if ! [ -s "$out" ] ; then	
			echo Detected: $out does not exist
			bad=true
		elif [ "$out" -ot "$script" ] ; then
			echo Detected: $out is older than $script
			bad=true  # at this stage output file is newer than script
		elif [ -s "$log" ] && ! tail -n1 "$log" | grep -q Finished ; then
			echo Detected: $log did not finish. Last lines are
			tail "$log"
			echo ""
			bad=true
		fi

		if [ "$bad" == "true" ] ; then
			if grep $point $queue | grep -q $num; then 
				echo $nameExec for point $point at $num/$job is still running. Just wait.
			elif [ "$rep" == "true" ] ; then
				repair=(${repair[@]} "$num")
				echo Point $point will be repaired at $num/$job
			else
				echo $nameExec failed for point $point at $num/$job. You can resubmit with -f to repair
			fi
		fi
	done

	for rr in "${repair[@]}" ; do

		echo Repairing $point at $rr/$job

		this=$outdir/this_sensitivity.card
		if ! [ -s "$this" ] ; then
			# take cards from upper folder
			card=$outdir/../multi.card
			fitc=$outdir/../fit_options.card
			oscc=$outdir/../oscillation.card
			atmo=$outdir/../beam_sample.card
			beam=$outdir/../atmo_sample.card
			if ! [ -s "$card" ] ; then
				echo ERROR There is no main card $(realpath $card), very bad!
				exit 1
			fi

			sed -i "s:^point.*:point\t$t:" $card
			sed -i "s:^output.*:output\t\"$outdir/SpaghettiSens.root\":" $card

			cp $card $this
			sed -i "s:^fit_parameters.*:fit_parameters\t\"$fitc\":" $this
			sed -i "s:^oscillation_parameters.*:oscillation_parameters\t\"$oscc\":" $this
			sed -i "s:^beam_parameters.*:beam_parameters\t\"$beam\":" $this
			sed -i "s:^atmo_parameters.*:atmo_parameters\t\"$atmo\":" $this
		fi


		recover=$outdir/Recover.$rr.sub
		echo $outdir
		echo $recover
		echo $outlog/L$nameExec.$rr.log
		if [ "$SCHED" == "HTCONDOR" ] ; then
			cat > $recover << EOF
#! /bin/bash
# script submission for condor
# sumbit with --
#	$sub $recover

executable		= $Sens
arguments		= $rr $job $this
getenv			= True
should_transfer_files	= IF_NEEDED
when_to_transfer_output	= ON_EXIT
initialdir		= $PWD
output			= $outlog/L$nameExec.$rr.log
log 			= $outlog/Logfile$nameExec.$rr.log
error			= $outlog/L$nameExec.$rr.log
stream_output		= True
stream_error		= True
+JobFlavour="testmatch"

queue

EOF
		elif [ "$SCHED" == "SLURM" ] ; then
			cat > $recover << EOF
#! /bin/bash
# script submission for Slurm
# sumbit with --
#	$sub $recover

#SBATCH --job-name=fixing
#SBATCH -o $log
#SBATCH -p nms_research,shared
#SBATCH --time=3-0
#SBATCH --cpus-per-task=1

srun $Sens fitter $rr $job $this

EOF
		fi
		$sub $recover
	done
done < $pointfile

if [ "${#repeat[@]}" -gt 0 ] ; then
	point_file=".points_list"
	echo "${repeat[@]}" > $point_file
	card=$root/multi.card
	if ! [ -s "$card" ] ; then
		echo ERROR There is no main card $(realpath $card), very bad!
		exit 1
	fi

	scan=""
	if [[ "$1" =~ .*CPV.* ]] ; then
		scan="-f CPV"
	fi
	$PWD/$trisens -x $scan -r $root -p $point_file -N 500
fi
