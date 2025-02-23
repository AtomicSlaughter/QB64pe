#!/bin/bash
# Arg 1: qb54 location
# Arg 2: Optional category to test

PREFIX="Compilation"

RESULTS_DIR="./tests/results/$PREFIX"

mkdir -p $RESULTS_DIR

QB64=$1

if [ "$#" -eq 2 ]; then
    CATEGORY="/$2"
fi

show_failure()
{
    cat "$RESULTS_DIR/$1-$2-compile_result.txt"
    cat "$RESULTS_DIR/$2-compilelog.txt"
}

show_incorrect_result()
{
    printf "EXPECTED: '%s'\n" "$1"
    printf "GOT:      '%s'\n" "$2"
}


# Each .bas file represents a separate test.
while IFS= read -r test
do 
    category=$(basename "$(dirname "$test")")
    testName=$(basename "$test" .bas)

    TESTCASE="$category/$testName"
    EXE="$RESULTS_DIR/$category-$testName - output"

    # If a .err file exists, then this test is actually testing a compilation error
    testType="success"
    if test -f "./tests/compile_tests/$category/$testName.err"; then
        testType="error"
    fi

    # Clear out temp folder before next compile, avoids stale compilelog files
    rm -fr ./internal/temp/*

    # Clean up existing EXE, so we don't use it by accident
    rm -f "$EXE*"

    compileResultOutput="$RESULTS_DIR/$category-$testName-compile_result.txt"

    # A .flags file contains any extra compiler flags to provide to QB64 for this test
    compilerFlags=
    if test -f "./tests/compile_tests/$category/$testName.flags"; then
        compilerFlags=$(cat "./tests/compile_tests/$category/$testName.flags")
    fi

    # -m and -q make sure that we get predictable results
    "$QB64" $compilerFlags -m -q -x "./tests/compile_tests/$category/$testName.bas" -o "$EXE" 1>"$compileResultOutput"
    ERR=$?
    cp_if_exists ./internal/temp/compilelog.txt "$RESULTS_DIR/$category-$testName-compilelog.txt"

    if [ "$testType" == "success" ]; then
        (exit $ERR)
        assert_success_named "Compile" "Compilation Error:" show_failure "$category" "$testName"

        test -f "$EXE"
        assert_success_named "exe exists" "$test-output executable does not exist!" show_failure "$category" "$testName"

        # Some tests do not have an output or err file because they should
        # compile successfully but cannot be run on the build agents
        if [ ! -f "./tests/compile_tests/$category/$testName.output" ]; then
            continue
        fi

        expectedResult="$(cat "./tests/compile_tests/$category/$testName.output")"

        pushd . > /dev/null
        cd "./tests/compile_tests/$category"
        testResult=$("../../../$EXE" 2>&1)
        ERR=$?
        popd > /dev/null

        (exit $ERR)
        assert_success_named "run" "Execution Error:" echo "$testResult"

        [ "$testResult" == "$expectedResult" ]
        assert_success_named "result" "Result is wrong:" show_incorrect_result "$expectedResult" "$testResult"

        # Restart pulseaudio between each test to make sound tests work on Linux
        if [ "$CI_TESTING" == "y" ] && command -v pulseaudio > /dev/null
        then
            pulseaudio -k
            pulseaudio -D
        fi
    else
        ! (exit $ERR)
        assert_success_named "Compile" "Compilation Success, was expecting error:" show_failure "$category" "$testName"

        ! test -f "$EXE"
        assert_success_named "Exe exists" "'$category-$testName - output' exists, it should not!" show_failure "$category" "$testName"

        expectedErr="$(cat "./tests/compile_tests/$category/$testName.err")"

        diffResult=$(diff -y "./tests/compile_tests/$category/$testName.err" "$compileResultOutput")
        assert_success_named "Error result" "Error reporting is wrong:" echo "$diffResult"
    fi
done < <(find ./tests/compile_tests$CATEGORY -name "*.bas" -print)
