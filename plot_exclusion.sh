#!/bin/bash

#############################
#### user defined options ###
#############################


# output name unique to combination of sets
# this name will be used to refer to each output file
name="cpv_comb_summary"

# list of files with CPV exclusion curves
# these are the output of the exclude.sh script
# and should be text file with CPV sensitivies
model=("/eos/home-l/lamuntea/HK/errorstudy/CPV_comb/NH_IH/contours/CPV_scan.dat"
       "/afs/cern.ch/work/l/lamuntea/HK/errorstudy/CPV_comb/NH_NH/contours/CPV_scan.dat"
       "/eos/home-l/lamuntea/HK/errorstudy/CPV_comb/NH/contours/CPV_scan.dat")

# names for displaying above results
# this will be used by gnuplot to label the curves
# in the plots and correspond to the input files above
nickn=("nhih" 
       "nhnh"
       "unknownMH")



###################################
#### do not modify script below ###
###################################

usage="usage: $0 [-p output] [-h]
			
Render plots out of the exclusion (see exclusion.sh) and save them to PDF.
In order to use this script, the user should open it with their favourite editor
and modify the first block accordingly. All the outputs will be saved under the 
plot folder, where the plotting scripts are located.
Please refer to the documentation if this is not clear.

It requires gnuplot and texlive to produce the final PDF.

Options
    -p [<file>]  the plots are saved in a single PDF <file>; if omitted, 
    		 the output is by default \"./plot/$name/plot_bundle.pdf\"
    -h		 print this message and exit
"

pdf=false
out=""
while getopts 'r:d:1:2:N:t:m:sf:p:xv:h' flag; do
	case "${flag}" in
		p) pdf=true
		   out="${OPTARG}" ;;
		h) echo "$usage" >&2
		   exit 0 ;;
		*) printf "illegal option -%s\n" "$OPTARG" >&2
		   echo "$usage" >&2
		   exit 1 ;;
	esac
done


Sens=bin/dropsens

echo Creating dir plot/$name
mkdir -p plot/$name
card=plot/$name/$name.card

rm $lims $olim $card

for i in ${!model[*]}; do 
	m="${model[$i]}"
	echo "${nickn[$i]}" \"$m\" >> $card
done

echo Extract exclusion information
$Sens $card


if [ $name ] ; then
	ssfile=($(ls exclusion_*.dat))

	for f in ${ssfile[@]}; do
		echo $f
		mv $f plot/$name/$name'_'$f
	done
fi

option="dataset=\"$name\""

plot=( "sens.gpl"
       "sens_detail.gpl" )

cd plot

for p in "${plot[@]}" ; do
	/afs/cern.ch/user/l/lamuntea/software/gnuplot/bin/gnuplot -e "$option" $p
done

echo mv -f $name"*.*" $name/
mv -f $name*.* $name/

cd ..

if [ "$pdf" == "true" ] ; then
	if [ -z $out ] ; then
		out="plot_bundle.tex"
	fi

	./bin/plot_bundle $out plot/$name/$name'_'*.tex
fi
