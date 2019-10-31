#! /bin/bash

sens=./bisens.sh
pena=./penalise.sh
cont=./contour.sh

study="/home/tboschi/data/errorstudy"
point="asim"
#point="asim"

model=("nuenorm1_corr" "nuenorm2_corr" "nuenorm3_corr" "nuenorm4_corr" "nuenorm5_corr"
       "nuenorm1_anti" "nuenorm2_anti" "nuenorm3_anti" "nuenorm4_anti" "nuenorm5_anti")
#model=("8" "11a" "11b")

for mod in "${model[@]}"
do
	$sens -g $study/global/$point -r $study/$mod/$point -1 NH -2 NH
done

while [ $(qstat -u tboschi | grep tboschi | wc -l) -gt 0 ]
do
	echo 'waiting for jobs to end...'
	sleep 600
done

for mod in "${model[@]}"
do
	$pena -r $study/$mod/$point/NH_NH/
	$cont -r $study/$mod/$point/NH_NH/
done

#pid=$(ps -opid= -C bisens.sh | tr -d '[:space:]')
#echo /proc/$pid
#while [ -n "$pid" -a -d "/proc/$pid" ] ; do
#	sleep 60
#done
