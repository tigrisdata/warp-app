# Object Store Distributed Benchmark Tool

This repository contains a tool that automates running warp distributed benchmarks
against S3 compatible services. It is designed to work with Fly.io. The benchmark
tool follows a client-server model where the server coordinates the benchmark and
the clients run the actual benchmark.

The benchmark tool uses [warp](https://raw.githubusercontent.com/minio/warp/master/warp_logo.png) under the hood.

# Prerequisites

- [Fly.io](https://fly.io) account
- [Flyctl](https://fly.io/docs/getting-started/installing-flyctl/) installed
- Access to an S3 compatible object storage service and pre-created bucket

Once you have a Fly.io account, modify the `fly.toml` file and choose an appropriate name for your app.
Then run `flyctl launch --no-deploy` to create the app.

Once the application is created you are all set to run benchmarks.

# Usage

There are several configuration options available that you can see below:

```
$ ./benchmark.sh -h
A utility to run S3 benchmarks on Fly.io

Usage: benchmark.sh [-r|-n|-c|-o|-e|-a|-p|-b|-d|-s|-h]
r             - regions to run the benchmark in (default: iad)
n             - number of warp client nodes per region to run the benchmark (default: 2)
c             - per warp client concurrency (default: 10)
o             - objects size (default: 4KB)
e             - S3 endpoint to use (default: idev-storage.fly.tigris.dev)
a             - S3 access key
p             - S3 secret key
b             - S3 bucket to use (default: test-bucket)
d             - duration of the benchmark (default: 1m)
t             - type of workload to run (get|mixed|list|stat default: get)
i             - use insecure connections to the S3 endpoint (default: false)
f             - randomize size of objects up to a max defined by [-o] (default: false)
g             - use range requests (default: false)
s             - shutdown the warp nodes
h             - help
```

## Running the benchmark with default workload options

To run the benchmark with default options simply run it as follows:

```bash
./benchmark.sh -a <access_key> -p <secret_key> -b test-bucket
```

This will benchmark the object storage service at `https://idev-storage.fly.tigris.dev` with the following parameters:

- region: `iad,ord,sjc`
- number of warp client nodes per region: `2`
- concurrency: `10`
- object size: `4KB`
- duration: `1m`
- bucket: `test-bucket`

There will be a total of `7` Fly machines created. One of them will be the server coordianting
the benchmark and the other `6` will be the clients running the actual benchmark (2 per region).

Each of the clients will have `10` concurrent connections to upload and download the objects.

The first phase (the prepare phase) of the benchmark will upload `2500` objects of size `4KB`
per client to the bucket `test-bucket`.

The second phase will benchmark get operations and attempt to download as many objects it
can within a duration of `1m`.
When downloading, objects are chosen randomly between all uploaded data and the benchmark
will attempt to run `10` concurrent downloads per client. In the default configuration
shown above, this will result in 40 concurrent downloads.

## Configuring the benchmark

### Object Size

To choose a different object size use the `-o` option:

```bash
./benchmark.sh -a <access_key> -p <secret_key> -b test-bucket -o 1MB
```

### Random Object Sizes

It is possible to randomize object sizes by specifying `-f` and objects will have a "random" size up to `-o`.

```bash
./benchmark.sh -a <access_key> -p <secret_key> -b test-bucket -o 1MB -f
```

However, there are some things to consider "under the hood".

Under the hood `warp` uses log2 to distribute objects sizes.
This means that objects will be distributed in equal number for each doubling of the size.
This means that `o/64` -> `o/32` will have the same number of objects as `o/2` -> `o`.

### Concurrency

All benchmarks operate concurrently. By default, 10 operations will run concurrently per Fly machine.
This can however also be tweaked using the `-c` parameter.

Tweaking concurrency can have an impact on performance, especially if latency to the server is tested.
Most benchmarks will also use different prefixes for each "thread" running.

## Benchmark Results

When benchmarks have finished an analysis will be shown.

```bash
$ ./benchmark.sh -a <access_key> -p <secret_key> -b test-bucket

----------------------------------------
Operation: PUT (15000). Ran 27s. Size: 4000 bytes. Concurrency: 60. Warp Instances: 6.

Requests considered: 10659:
 * Avg: 85ms, 50%: 80ms, 90%: 127ms, 99%: 170ms, Fastest: 26ms, Slowest: 511ms, StdDev: 37ms

Throughput:
* Average: 2.68 MiB/s, 701.62 obj/s

Throughput, split into 15 x 1s:
 * Fastest: 3.2MiB/s, 837.01 obj/s (1s, starting 03:55:27 UTC)
 * 50% Median: 2.8MiB/s, 727.32 obj/s (1s, starting 03:55:33 UTC)
 * Slowest: 2.2MiB/s, 577.45 obj/s (1s, starting 03:55:38 UTC)

----------------------------------------
Operation: GET (1275209). Ran 1m0s. Size: 4000 bytes. Concurrency: 60. Warp Instances: 6.

Requests considered: 1274705:
 * Avg: 3ms, 50%: 2ms, 90%: 5ms, 99%: 8ms, Fastest: 1ms, Slowest: 422ms, StdDev: 2ms
 * TTFB: Avg: 3ms, Best: 1ms, 25th: 2ms, Median: 2ms, 75th: 3ms, 90th: 5ms, 99th: 7ms, Worst: 422ms StdDev: 2ms
 * First Access: Avg: 3ms, 50%: 2ms, 90%: 5ms, 99%: 9ms, Fastest: 1ms, Slowest: 40ms, StdDev: 2ms
 * First Access TTFB: Avg: 3ms, Best: 1ms, 25th: 2ms, Median: 2ms, 75th: 5ms, 90th: 5ms, 99th: 8ms, Worst: 40ms StdDev: 2ms
 * Last Access: Avg: 3ms, 50%: 2ms, 90%: 5ms, 99%: 8ms, Fastest: 1ms, Slowest: 33ms, StdDev: 2ms
 * Last Access TTFB: Avg: 3ms, Best: 1ms, 25th: 2ms, Median: 2ms, 75th: 5ms, 90th: 5ms, 99th: 8ms, Worst: 33ms StdDev: 2ms

Throughput:
* Average: 81.07 MiB/s, 21253.28 obj/s

Throughput, split into 59 x 1s:
 * Fastest: 83.3MiB/s, 21837.10 obj/s (1s, starting 03:56:10 UTC)
 * 50% Median: 81.3MiB/s, 21307.31 obj/s (1s, starting 03:56:23 UTC)
 * Slowest: 76.6MiB/s, 20069.42 obj/s (1s, starting 03:56:08 UTC)
```

All analysis will be done on a reduced part of the full data.
The data aggregation will _start_ when all threads have completed one request
and the time segment will _stop_ when the last request of a thread is initiated.

This is to exclude variations due to warm-up and threads finishing at different times.
Therefore the analysis time will typically be slightly below the selected benchmark duration.

Example:

```
Operation: GET (261320). Ran 1m0s. Size: 4000 bytes. Concurrency: 40. Warp Instances: 4.

Throughput:
* Average: 16.62 MiB/s, 4356.26 obj/s
```

The benchmark run is then divided into fixed duration _segments_ of 1s each.
For each segment the throughput is calculated across all threads.

The analysis output will display the fastest, slowest and 50% median segment.

```
Throughput, split into 59 x 1s:
 * Fastest: 19.6MiB/s, 5141.23 obj/s (1s, starting 00:55:55 UTC)
 * 50% Median: 18.2MiB/s, 4759.79 obj/s (1s, starting 00:55:47 UTC)
 * Slowest: 5.9MiB/s, 1544.59 obj/s (1s, starting 00:55:17 UTC)
```

The per request statistics are also displayed.

- `TTFB` is the time from request was sent to the first byte was received.
- `First Access` is the first access per object.
- `Last Access` is the last access per object.

The fastest and slowest request times are shown, as well as selected
percentiles and the total amount is requests considered.

## Cleaning up the Fly machines

Once you are done with the benchmarks you can destroy the Fly machines by running:

```
./benchmark.sh -s
```
