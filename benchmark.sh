#!/bin/bash
# A Bash script to execute a Benchmark about implementation of Gateway pattern for Spring Cloud

echo "Gateway Benchmark Script"

OSX="OSX"
WIN="WIN"
LINUX="LINUX"
UNKNOWN="UNKNOWN"
PLATFORM=$UNKNOWN

RUN_ROUNDS=2
RUN_TIME=10s

function detectOS() {

    if [[ "$OSTYPE" == "linux-gnu" ]]; then
        PLATFORM=$LINUX
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        PLATFORM=$OSX
    elif [[ "$OSTYPE" == "cygwin" ]]; then
        PLATFORM=$WIN
    elif [[ "$OSTYPE" == "msys" ]]; then
        PLATFORM=$WIN
    elif [[ "$OSTYPE" == "win32" ]]; then
        PLATFORM=$WIN
    else
        PLATFORM=$UNKNOWN
    fi

    echo "Platform detected: $PLATFORM"
    echo

    if [ "$PLATFORM" == "$UNKNOWN" ]; then
        echo "Sorry, this platform is not recognized by this Script."
        echo
        echo "Open a issue if the problem continues:"
        echo "https://github.com/spencergibb/spring-cloud-gateway-bench/issues"
        echo
        exit 1
    fi

}

function detectGo() {

    if type -p go; then
        echo "Found Go executable in PATH"
    else
        echo "Not found Go installed"
        exit 1
    fi

}

function detectJava() {

    if type -p java; then
        echo "Found Java executable in PATH"
    else
        echo "Not found Java installed"
        exit 1
    fi

}

function detectMaven() {

    if type -p mvn; then
        echo "Found Maven executable in PATH"
    else
        echo "Not found Maven installed"
        exit 1
    fi

}

function detectOpenresty() {

    if type -p openresty; then
        echo "Found Maven executable in PATH"
    else
        echo "Not found Openresty installed"
        exit 1
    fi

}

function detectWrk() {

    if type -p wrk; then
        echo "Found wrk executable in PATH"
    else
        echo "Not found wrk installed"
        exit 1
    fi

}

function setup(){

    detectOS

    #detectGo
    detectJava
    #detectMaven
    detectOpenresty

    detectWrk

    mkdir -p reports
    rm ./reports/*.txt
}

setup

#Launching the different services

function runStatic() {

    cd static
    if [ "$PLATFORM" == "$OSX" ]; then
        GOOS=darwin GOARCH=amd64 go build -o webserver.darwin-amd64 webserver.go
        ./webserver.darwin-amd64
    elif [ "$PLATFORM" == "$LINUX" ]; then
        # go build -o webserver webserver.go
        ./webserver > /dev/null 2>&1
        exit 1
    elif [ "$PLATFORM" == "$WIN" ]; then
        echo "Googling"
        exit 1
    else
        echo "Googling"
        exit 1
    fi

}

function prepareZuul() {
    echo "Preparing Gateway Zuul"
    cd zuul
    ./mvnw clean package
    cd ..
}

function runZuul() {

    echo "Running Gateway Zuul"

    cd zuul
    java -jar target/zuul-0.0.1-SNAPSHOT.jar
}

function prepareGateway() {
    echo "Preparing Spring Gateway"
    cd gateway
    ./mvnw clean package
    cd ..
}

function runGateway() {

    echo "Running Spring Gateway"

    cd gateway
    java -jar target/gateway-0.0.1-SNAPSHOT.jar
}

function runLinkerd() {

    echo "Running Gateway Linkerd"

    cd linkerd
    java -jar linkerd-1.3.4.jar linkerd.yaml
}

function runOpenresty() {

    echo "Running Openresty"

    cd openresty
    openresty -p `pwd` -c openresty.conf
}

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
        echo "** Trapped CTRL-C"
        kill $(ps aux | grep './webserver.darwin-amd64' | awk '{print $2}')
        kill $(ps aux | grep 'openresty' | awk '{print $2}')
        kill $(jps -l | grep 'zuul-' | awk '{print $1}')
        kill $(jps -l | grep 'gateway-' | awk '{print $1}')
        kill $(jps -l | grep 'linkerd-' | awk '{print $1}')
        exit 1
}

#Run Static web server
runStatic &

echo "Verifying static webserver is running"

response=$(curl http://localhost:8000/hello.txt)
if [ '{output:"I Love Spring Cloud"}' != "${response}" ]; then
    echo
    echo "Problem running static webserver, response: $response"
    echo
    exit 1
fi;

echo "Wait 3"
sleep 3

function runGateways() {
    echo "Preparing tools"
#    prepareZuul
#    prepareGateway

    echo "Run Gateways"
    runZuul &
    runGateway &
    runLinkerd &
    runOpenresty &

}

runGateways

#Execute performance tests

function warmup() {

    echo "JVM Warmup"

    for run in {1..$RUN_ROUNDS}
    do
      wrk -t 10 -c 200 -d $RUN_TIME http://localhost:8082/hello.txt >> ./reports/gateway.txt
    done

    for run in {1..$RUN_ROUNDS}
    do
      wrk -H "Host: web" -t 10 -c 200 -d $RUN_TIME http://localhost:4140/hello.txt >> ./reports/linkerd.txt
    done

    for run in {1..$RUN_ROUNDS}
    do
      wrk -t 10 -c 200 -d $RUN_TIME http://localhost:8081/hello.txt >> ./reports/zuul.txt
    done

    for run in {1..$RUN_ROUNDS}
    do
      wrk -t 10 -c 200 -d $RUN_TIME http://localhost:20000/hello.txt >> ./reports/openresty.txt
    done
}

function runPerformanceTests() {

    echo "Static results"
    wrk -t 10 -c 200 -d 30s  http://localhost:8000/hello.txt > ./reports/static.txt

    echo "Wait 10 seconds"
    sleep 10

    warmup
}

runPerformanceTests

ctrl_c
echo "Script Finished"
