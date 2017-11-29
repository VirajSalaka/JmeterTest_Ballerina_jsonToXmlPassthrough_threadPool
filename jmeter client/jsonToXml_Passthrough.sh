#!/bin/bash
if [[ -d results ]]; then
    echo "Results directory already exists"
    exit 1
fi

jmeter_dir=""
for dir in $HOME/apache-jmeter*; do
    [ -d "${dir}" ] && jmeter_dir="${dir}" && break
done
export JMETER_HOME="${jmeter_dir}"
export PATH=$JMETER_HOME/bin:$PATH

concurrent_users=(500)
backend_sleep_time=(10)
threadpool_size=(500)
ballerina_host=10.10.10.12
ballerina_path=/passthrough
ballerina_ssh_host=ballerina_host
backend_ssh_host=netty_host
# test duration in seconds
test_duration=900
# warmuptime in minutes
warmup_time=5
jmeter1_host=10.10.10.10
jmeter1_ssh_host=jmeter1

mkdir results
cp $0 results

write_server_metrics() {
    server=$1
    ssh_host=$2
    pgrep_pattern=$3
    command_prefix=""
    if [[ ! -z $ssh_host ]]; then
        command_prefix="ssh $ssh_host"
    fi
    $command_prefix ss -s > ${report_location}/${server}_ss.txt
    $command_prefix uptime > ${report_location}/${server}_uptime.txt
    $command_prefix sar -q > ${report_location}/${server}_loadavg.txt
    $command_prefix sar -A > ${report_location}/${server}_sar.txt
    $command_prefix top -bn 1 > ${report_location}/${server}_top.txt
    if [[ ! -z $pgrep_pattern ]]; then
        $command_prefix ps u -p \`pgrep -f $pgrep_pattern\` > ${report_location}/${server}_ps.txt
    fi
}

for tsize in ${threadpool_size[@]}
do
    for sleep_time in ${backend_sleep_time[@]}
    do
        for u in ${concurrent_users[@]}
        do
            report_location=$PWD/results/${tsize}Threads/${sleep_time}ms_sleep/${u}_users
            echo "Report location is ${report_location}"
            mkdir -p $report_location

            ssh $ballerina_ssh_host "./setup.sh $tsize"
            ssh $backend_ssh_host "./netty-service/netty-start.sh $sleep_time"
            ssh $jmeter1_ssh_host "./jmeter/jmeter-server-start.sh $jmeter1_host"
			
            export JVM_ARGS="-Xms2g -Xmx2g -XX:+PrintGC -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:$report_location/jmeter_gc.log"
            echo "# Running JMeter. Concurrent Users: $u Duration: $test_duration JVM Args: $JVM_ARGS"
            jmeter -n -t apim-test.jmx -R $jmeter1_host -X \
                -Gusers=$u -Gduration=$test_duration -Ghost=$ballerina_host -Gpath=$ballerina_path \
                -Gpayload=$HOME/1024B.json -Gresponse_size=1024B  \
                -Gprotocol=http -l ${report_location}/results.jtl
			
            write_server_metrics jmeter
            write_server_metrics ballerina_host $ballerina_ssh_host ballerina
            write_server_metrics netty $backend_ssh_host netty

            $HOME/jtl-splitter/jtl-splitter.sh ${report_location}/results.jtl $warmup_time
            echo "Generating Dashboard for Warmup Period"
            jmeter -J jmeter.reportgenerator.statistic_window=10000000 -g ${report_location}/results-warmup.jtl -o $report_location/dashboard-warmup
            echo "Generating Dashboard for Measurement Period"
            jmeter -J jmeter.reportgenerator.statistic_window=10000000 -g ${report_location}/results-measurement.jtl -o $report_location/dashboard-measurement

            echo "Zipping JTL files in ${report_location}"
            zip -jm ${report_location}/jtls.zip ${report_location}/results*.jtl
         
            touch ${report_location}/bre.log
            touch ${report_location}/ballerina_host_gc.log
            touch ${report_location}/netty.log
            touch ${report_location}/netty_gc.log
            scp $jmeter1_ssh_host:jmetergc.log ${report_location}/jmeter1_gc.log
            scp $ballerina_ssh_host:ballerina-tools-0.93.1-SNAPSHOT/logs/bre.log ${report_location}/bre.log
            scp $ballerina_ssh_host:ballerina-tools-0.93.1-SNAPSHOT/logs/gc.log ${report_location}/ballerina_host_gc.log
            scp $backend_ssh_host:netty-service/logs/netty.log ${report_location}/netty.log
            scp $backend_ssh_host:netty-service/logs/nettygc.log ${report_location}/netty_gc.log
        done
    done
done

			
echo "completed"


