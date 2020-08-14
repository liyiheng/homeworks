#!/bin/env bash
./bin/pd-server --name=pd1 \
                --data-dir=data/pd1 \
                --client-urls="http://127.0.0.1:2379" \
                --peer-urls="http://127.0.0.1:2380" \
                --initial-cluster="pd1=http://127.0.0.1:2380" \
                --log-file=data/pd1.log &

./bin/tikv-server --pd-endpoints="127.0.0.1:2379" \
                --addr="127.0.0.1:20160" \
                --data-dir=data/tikv1 \
                --log-file=data/tikv1.log &
./bin/tikv-server --pd-endpoints="127.0.0.1:2379" \
                --addr="127.0.0.1:20161" \
                --data-dir=data/tikv2 \
                --log-file=data/tikv2.log &
./bin/tikv-server --pd-endpoints="127.0.0.1:2379" \
                --addr="127.0.0.1:20162" \
                --data-dir=data/tikv3 \
                --log-file=data/tikv3.log &

./bin/tidb-server --store tikv --path 127.0.0.1:2379 \
		--log-file=data/tidb.log &
