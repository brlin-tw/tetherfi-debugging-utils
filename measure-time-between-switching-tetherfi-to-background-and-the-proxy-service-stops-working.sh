#!/usr/bin/env bash
# Measure time between switching TetherFi to the background and the proxy service stops working
#
# Copyright 2023 林博仁(Buo-ren, Lin) <buo.ren.lin@gmail.com>
# SPDX-License-Identifier: CC-BY-SA-4.0+
TETHERFI_HANG_THRESHOLD_SECONDS="${TETHERFI_HANG_THRESHOLD_SECONDS:-3}"
TEST_URL="${TEST_URL:-http://google.com}"
INTERVAL_BETWEEN_TEST_SECONDS="${INTERVAL_BETWEEN_TEST_SECONDS:-0.5}"
TETHERFI_RESUME_THRESHOLD_SECONDS="${TETHERFI_RESUME_THRESHOLD_SECONDS:-2}"

set_opts=(
    # Terminate script execution when an unhandled error occurs
    -o errexit
    -o errtrace

    # Terminate script execution when an unset parameter variable is
    # referenced
    -o nounset
)
if ! set "${set_opts[@]}"; then
    printf \
        'Error: Unable to set the defensive interpreter behavior.\n' \
        1>&2
    exit 1
fi

regex_positive_float_number='^[[:digit:]]+(\.[[:digit:]]+)?$'
if ! [[ "${TETHERFI_HANG_THRESHOLD_SECONDS}" =~ ${regex_positive_float_number} ]]; then
    printf \
        'Error: The value of the TETHERFI_HANG_THRESHOLD_SECONDS parameter is invalid, a positive float number is expected.\n' \
        1>&2
    exit 1
fi

if ! [[ "${TETHERFI_RESUME_THRESHOLD_SECONDS}" =~ ${regex_positive_float_number} ]]; then
    printf \
        'Error: The value of the TETHERFI_RESUME_THRESHOLD_SECONDS parameter is invalid, a positive float number is expected.\n' \
        1>&2
    exit 1
fi

if ! [[ "${INTERVAL_BETWEEN_TEST_SECONDS}" =~ ${regex_positive_float_number} ]]; then
    printf \
        'Error: The value of the INTERVAL_BETWEEN_TEST_SECONDS parameter is invalid, a positive float number is expected.\n' \
        1>&2
    exit 1
fi

test_url_protocol=
if test "${TEST_URL#http://}" != "${TEST_URL}"; then
    test_url_protocol=http
elif test "${TEST_URL#https://}" != "${TEST_URL}"; then
    test_url_protocol=https
else
    printf \
        'Error: The value of the TEST_URL parameter(%s) is not supported.\n' \
        "${TEST_URL}" \
        1>&2
    exit 1
fi

case "${test_url_protocol}" in
    http)
        if ! test -v http_proxy \
            && ! test -v HTTP_PROXY; then
            printf \
                'Error: HTTP proxy environment variables not set.\n' \
                1>&2
            exit 1
        fi
    ;;
    https)
        if ! test -v https_proxy \
            && ! test -v HTTPS_PROXY; then
            printf \
                'Error: HTTP proxy environment variables not set.\n' \
                1>&2
            exit 1
        fi
    ;;
    *)
        printf \
            'FATAL: Unsupported test_url_protocol value detected, contact support for help.\n' \
            1>&2
        exit 99
    ;;
esac

printf \
    'Info: Please press the Enter key of the computer after switching the TetherFi application to foreground:'

# The enter variable is just a placeholder for readability
# shellcheck disable=SC2034
read -r enter

printf \
    'Info: Checking whether the proxy service is working in the first place...\n'
curl_opts=(
    # We don't care about the request body
    --head

    # We also don't care about the response header
    --output /dev/null

    # Fail when HTTP return status is wrong
    --fail

    # Don't print progress meter but still print error messages
    --silent
    --show-error

    # Timeout threshold for the entire operation
    --max-time "${TETHERFI_HANG_THRESHOLD_SECONDS}"
)
if ! curl "${curl_opts[@]}" "${TEST_URL}"; then
    printf \
        'Error: Proxy request failed before testing, please check your proxy connection and TetherFi settings.\n' \
        1>&2
    exit 2
fi

printf \
    'Info: Okay, proxy seems to be working at the moment.  Please press the Enter key of the computer and switch the TetherFi application to the background AT THE SAME TIME:'

# The enter variable is just a placeholder for readability
# shellcheck disable=SC2034
read -r enter

printf \
    'Info: Recording the test start time...\n'
if ! test_start_time_epoch="$(date +%s)"; then
    printf \
        'Error: Failed to record the test start time.\n' \
        1>&2
    exit 2
fi

printf \
    'Info: Detecting timeout incident...'
curl_exit_status=0
while true; do
    curl "${curl_opts[@]}" "${TEST_URL}" || curl_exit_status="${?}"
    if test "${curl_exit_status}" -ne 0; then
        if test "${curl_exit_status}" -ne 28; then
            printf \
                'Error: Other curl error occurred, consider increase the TETHERFI_HANG_THRESHOLD_SECONDS or change the TEST_URL.\n' \
                1>&2
            exit 3
        fi

        printf \
            'Warning: TetherFi proxy service timeout detected!\n' \
            1>&2
        break
    fi

    if ! last_successful_test_time_epoch="$(date +%s)"; then
        printf \
            'Error: Failed to update last successful test time time.\n' \
            1>&2
        exit 2
    fi
    printf '.'
    sleep "${INTERVAL_BETWEEN_TEST_SECONDS}"
done

if ! test -v last_successful_test_time_epoch; then
    # Test never succeeded
    timeout_duration_seconds=0
else
    timeout_duration_seconds="$(( last_successful_test_time_epoch - test_start_time_epoch ))"
fi

printf \
    'Info: Timeout duration determined to be "%s" seconds.\n' \
    "${timeout_duration_seconds}"

printf \
    'Info: Please press the ENTER key and switch the TetherFi application back to the foreground AT THE SAME TIME:'

# The enter variable is just a placeholder for readability
# shellcheck disable=SC2034
read -r enter

printf \
    'Info: Recording the proxy functionality resume test start time...\n'
if ! resume_start_time_epoch="$(date +%s)"; then
    printf \
        'Error: Failed to record the proxy functionality resume test start time.\n' \
        1>&2
    exit 2
fi

printf \
    'Info: Detecting proxy service resume incident...'
curl_opts=(
    # We don't care about the request body
    --head

    # We also don't care about the response header
    --output /dev/null

    # Fail when HTTP return status is wrong
    --fail

    # Don't print progress meter but still print error messages
    --silent
    --show-error

    # Timeout threshold for the entire operation
    --max-time "${TETHERFI_RESUME_THRESHOLD_SECONDS}"
)
while true; do
    curl_exit_status=0
    curl "${curl_opts[@]}" "${TEST_URL}" 2>/dev/null || curl_exit_status="${?}"
    if test "${curl_exit_status}" -eq 0; then
        printf \
            '\nInfo: Proxy service resume detected.\n'
        if ! resume_end_time_epoch="$(date +%s)"; then
            printf \
                'Error: Failed to query the resume test end time.\n' \
                1>&2
            exit 2
        fi
        break
    fi

    if test "${curl_exit_status}" -ne 28; then
        printf \
            'Error: Other curl error occurred, consider increase the TETHERFI_RESUME_THRESHOLD_SECONDS or change the TEST_URL.\n' \
            1>&2
        exit 3
    fi

    printf '.'
    sleep "${INTERVAL_BETWEEN_TEST_SECONDS}"
done

resume_duration_seconds="$((
    resume_end_time_epoch - resume_start_time_epoch
))"

printf \
    'Info: Proxy service resume duration determined to be "%s" seconds.\n' \
    "${resume_duration_seconds}"

printf \
    'Info: Operation completed without errors.\n'
