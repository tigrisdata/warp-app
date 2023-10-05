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
r             - region to run the benchmark in (default: iad)
n             - number of warp client nodes to use to run the benchmark (default: 5)
c             - per warp client concurrency (default: 10)
o             - objects size (default: 4KB)
e             - S3 endpoint to use (default: dev-tigris-os.fly.dev)
a             - S3 access key
p             - S3 secret key
b             - S3 bucket to use (default: test-bucket)
d             - duration of the benchmark (default: 1m)
i             - use insecure connections to the S3 endpoint (default: false)
f             - randomize size of objects up to a max defined by [-o] (default: false)
s             - shutdown the warp nodes
h             - help
```

## Running the benchmark with default workload options

To run the benchmark with default options simply run it as follows:

```bash
./benchmark.sh -a <access_key> -p <secret_key> -b test-bucket
```

This will benchmark the object storage service at `https://dev-tigris-os.fly.dev` with the following parameters:

- region: `iad`
- number of warp client nodes: `5`
- concurrency: `10`
- object size: `4KB`
- duration: `1m`
- bucket: `test-bucket`

There will be a total of `5` Fly machines created. One of them will be the server coordianting
the benchmark and the other 4 will be the clients running the actual benchmark.

Each of the clients will have `10` concurrent connections to upload and download the objects.

The first phase (the prepare phase) of the benchmark will upload `2500` objects of size `4KB`
per client to the bucket `test-bucket`.

The second phase will benchmark get operations and attempt to download as many objects it
can within a duration of `1m`.
When downloading, objects are chosen randomly between all uploaded data and the benchmark
will attempt to run `10` concurrent downloads per client. In the default configuration
shown above, this will result in 40 concurrent downloads.

## Configuring the benchmark

By default warp uploads random data.

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
[INFO]  Checking if node exists... (name: warp-node-iad-0, vm-size: shared-cpu-4x)
[INFO]  Checking if node exists... (name: warp-node-iad-1, vm-size: shared-cpu-4x)
[INFO]  Checking if node exists... (name: warp-node-iad-2, vm-size: shared-cpu-4x)
[INFO]  Checking if node exists... (name: warp-node-iad-3, vm-size: shared-cpu-4x)
[INFO]  Checking if node exists... (name: warp-node-iad-4, vm-size: shared-cpu-4x)
[INFO]  Running workload (endpoint: dev-tigris-os.fly.dev, bucket: test-bucket, max object_size: 4KB, duration: 1m, concurrency: 10)...

----------------------------------------
Operation: PUT (10000). Ran 11s. Size: 4000 bytes. Concurrency: 40. Warp Instances: 4.

Requests considered: 9727:
 * Avg: 44ms, 50%: 39ms, 90%: 63ms, 99%: 89ms, Fastest: 22ms, Slowest: 139ms, StdDev: 15ms

Throughput:
* Average: 3.48 MiB/s, 912.01 obj/s

Throughput, split into 10 x 1s:
 * Fastest: 3.7MiB/s, 981.23 obj/s (1s, starting 00:55:12 UTC)
 * 50% Median: 3.5MiB/s, 920.27 obj/s (1s, starting 00:55:09 UTC)
 * Slowest: 3.3MiB/s, 855.88 obj/s (1s, starting 00:55:04 UTC)

----------------------------------------
Operation: GET (261320). Ran 1m0s. Size: 4000 bytes. Concurrency: 40. Warp Instances: 4.

Requests considered: 261081:
 * Avg: 9ms, 50%: 8ms, 90%: 13ms, 99%: 40ms, Fastest: 3ms, Slowest: 121ms, StdDev: 6ms
 * TTFB: Avg: 9ms, Best: 3ms, 25th: 6ms, Median: 7ms, 75th: 9ms, 90th: 13ms, 99th: 40ms, Worst: 121ms StdDev: 6ms
 * First Access: Avg: 29ms, 50%: 23ms, 90%: 50ms, 99%: 68ms, Fastest: 11ms, Slowest: 120ms, StdDev: 13ms
 * First Access TTFB: Avg: 29ms, Best: 11ms, 25th: 19ms, Median: 23ms, 75th: 35ms, 90th: 50ms, 99th: 67ms, Worst: 120ms StdDev: 13ms
 * Last Access: Avg: 8ms, 50%: 7ms, 90%: 11ms, 99%: 19ms, Fastest: 3ms, Slowest: 49ms, StdDev: 3ms
 * Last Access TTFB: Avg: 8ms, Best: 3ms, 25th: 7ms, Median: 7ms, 75th: 9ms, 90th: 11ms, 99th: 19ms, Worst: 49ms StdDev: 3ms

Throughput:
* Average: 16.62 MiB/s, 4356.26 obj/s

Throughput, split into 59 x 1s:
 * Fastest: 19.6MiB/s, 5141.23 obj/s (1s, starting 00:55:55 UTC)
 * 50% Median: 18.2MiB/s, 4759.79 obj/s (1s, starting 00:55:47 UTC)
 * Slowest: 5.9MiB/s, 1544.59 obj/s (1s, starting 00:55:17 UTC)
warp: Requesting stage cleanup start...
warp: Client [fdaa:2:3d6:a7b:1a7:1c7:37ea:2]:7761: Requested stage cleanup start...
warp: Client [fdaa:2:3d6:a7b:9d35:193e:25d7:2]:7761: Requested stage cleanup start...
warp: Client [fdaa:2:3d6:a7b:ab9:e00d:d7c2:2]:7761: Requested stage cleanup start...
warp: Client [fdaa:2:3d6:a7b:1b7:467d:498d:2]:7761: Requested stage cleanup start...
warp: Client [fdaa:2:3d6:a7b:1b7:467d:498d:2]:7761: Finished stage cleanup...
warp: Client [fdaa:2:3d6:a7b:ab9:e00d:d7c2:2]:7761: Finished stage cleanup...
warp: Client [fdaa:2:3d6:a7b:1a7:1c7:37ea:2]:7761: Finished stage cleanup...
warp: Client [fdaa:2:3d6:a7b:9d35:193e:25d7:2]:7761: Finished stage cleanup...
warp: Cleanup done.
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
