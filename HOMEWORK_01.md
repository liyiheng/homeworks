# TiDB 学习：Hello transaction

目标：在 TiDB 启动事务时打印 `Hello transaction` 的日志，并部署验证。

## 获取源码

```sh
proxychains git clone https://github.com/pingcap/tidb.git
proxychains git clone https://github.com/pingcap/pd.git
proxychains git clone https://github.com/tikv/tikv.git
```

## TiDB 事务启动入口

根据 `High performance TiDB` 课程的第一节，
TiDB 将 SQL 层的写操作转化为 KV 模型的多个操作，以事务的形式提交。
因此，为了在事务启动时打印日志，需要找到其执行写操作的入口。
大致思路为，顺着客户端请求的链路查看 TiDB 源码。

从程序入口可以看到，每个客户端建立连接后为其创建一个 goroutine 提供服务：

```go
// tidb-server/main.go
// runServer()
for {
	conn, err := s.listener.Accept()
	// 省略大量代码
	go s.onConn(clientConn)
}
```

顺着 onConn, 发现 `*clientConn.Run`, 从连接中读数据（客户端请求内容），
而后执行相应的逻辑，这里忽略其他代码，只关注可能的写操作：

```go
func (cc *clientConn) Run(ctx context.Context) {
	for {
		// 省略大量代码
		data, err := cc.readPacket()
		// 省略大量代码 err handling
		if err = cc.dispatch(ctx, data); err != nil {
		}
	}
}
func (cc *clientConn) dispatch(ctx context.Context, data []byte) error {
	// 省略大量代码
	switch cmd {
	// 省略大量代码
	case mysql.ComStmtExecute:
		return cc.handleStmtExecute(ctx, data)
}
func (cc *clientConn) handleStmtExecute(ctx context.Context, data []byte) (err error) {
	// 省略大量代码
	rs, err := stmt.Execute(ctx, args)
	// PrepareStmt, TiDBStatement implements it
}
```

这里发现 Execute 是一个接口的方法，
从它的实现 `*TiDBStatement.Execute` 中发现具体执行的是 TiDBContext 内部 session 的方法。
Session 也是一个接口，位于 `session/session.go` 的结构体 `session` 实现了该接口。

终于，在这里找到了 NewTxn 的实现：

```go
func (s *session) NewTxn(ctx context.Context) error {
	// 省略大量代码
}
```

在其中添加日志：

```text
diff --git a/session/session.go b/session/session.go
index 622688f59..e1a5cd0f5 100644
--- a/session/session.go
+++ b/session/session.go
@@ -1492,6 +1492,7 @@ func (s *session) isTxnRetryable() bool {
 }
 
 func (s *session) NewTxn(ctx context.Context) error {
+	logutil.Logger(ctx).Info("Hello transaction")
 	if s.txn.Valid() {
 		txnID := s.txn.StartTS()
 		err := s.CommitTxn(ctx)
```

## 部署和验证

### 编译

分别编译 pd、TiDB 、TiKV，得到以下二进制：

```text
pd-ctl
pd-recover
pd-server
tidb-server
tikv-ctl
tikv-server
```

### 部署

本机单节点部署 1 个 pd 实例， 3 个 TiKV 实例， 1 个 TiDB 实例。

根据相关文档，整理如下启动脚本:
```sh
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
```

各实例启动后，检查 TiKV 实例状态（省略大量字段）：

```sh
❯ bin/pd-ctl store -u http://127.0.0.1:2379
{
  "count": 3,
  "stores": [
    {
      "store": {
        "state_name": "Up"
      },
      "status": {}
    },
    {
      "store": {
        "state_name": "Up"
      },
      "status": {}
    },
    {
      "store": {
        "state_name": "Up"
      },
      "status": {}
    }
  ]
}
```

### 验证

通过 MySQL 客户端登录 TiDB, 创建测试表并插入一条记录：

```
mysql -h 127.0.0.1 -P 4000 -uroot
MySQL [(none)]> use test;
MySQL [test]> create table hello (id int auto_increment primary key, name varchar(64), score tinyint(4));
Query OK, 0 rows affected (2.276 sec)

MySQL [test]> insert into hello (name, score)
    -> values ('Alice', 99);
Query OK, 1 row affected (0.678 sec)
```

此时查看 TiDB 日志文件，发现成功打印 `Hello transaction`:

```
[2020/08/13 22:47:58.253 +08:00] [INFO] [session.go:1495] ["Hello transaction"]
```
