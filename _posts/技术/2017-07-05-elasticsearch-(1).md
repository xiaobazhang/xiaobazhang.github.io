##ElasticSearch（一）集群安装

### 1. 下载和运行

* ElasticSearch[官网](www.elastic.co/downloads) 下载最新版本的代码，最新5.x版本要求java版本1.8以上请注意。
* 解压源码包
 
  		tar -xvf elasticsearch-5.4.3.tar.gz 
  		cd elasticsearch-5.4.3
  		
* 单节点运行
		
		./bin/elasticsearch
		
	此时单节点已经运行起来了，浏览器输入以下命令：
		
		http://10.13.132.205:9200
		
	如果正常则返回结果格式如下：
		
		{
    		"name": "node-1",
    		"cluster_name": "suli-elasticsearch",
    		"cluster_uuid": "qd7_-1qtTx-USrsyrH8gUQ",
    		"version": {
        	"number": "5.4.3",
	        "build_hash": "eed30a8",
	        "build_date": "2017-06-22T00:34:03.743Z",
	        "build_snapshot": false,
	        "lucene_version": "6.5.1"
	    	},
		    "tagline": "You Know, for Search"
		}
		
* 有可能碰到的错误
	
	错误1
	
		[2017-07-05T21:12:54,036][ERROR][o.e.b.Bootstrap]
		[node-3] node validation exception
		[1] bootstrap checks failed
		[1]: max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
		
	这个错误是由于操作系统的vm.max_map_count设置太小导致的，解决如下
	
		sudo sysctl -w vm.max_map_count=655360
		
	错误2：
	
		max file descriptors [4096] for elasticsearch process likely too low, increase to at least [65536]
		
	这个错误是操作系统的最大文件打开数限制，解决如下：
	
		sudo vim /etc/security/limits.conf
				
* 此时基本已经可以基本运行了。

###2.多节点集群搭建

* 节点配置
	
	ElasticSearch集群中一共分为三种节点：master node、data node、client node。配置文件路径在elasticsearch-5.4.3/config/elasticsearch.yml
		
	1. master node:主要用于元数据(metadata)的处理,比如索引的增加、删除、分配分片等操作。	
	2. data node: 顾名思义该节点上保存了数据分片。他主要负责数据相关操作，比如分片的crud和搜索整合等业务。
	3. client node：client节点主要起到请求路由的功能，
	
	我使用了三台物理机，一台主master节点，一台client节点，一台data节点。
	
	1. master节点ip为10.13.132.205,该节点配置如下：
	
			cluster.name: suli-elasticsearch
			node.name: node-1
			node.master: true
			node.data: true
			network.host: 10.13.132.205
			discovery.zen.ping.unicast.hosts: ["10.13.132.205"]
			discovery.zen.ping.multicast.enabled: true
		
		其中cluster.name 三台配置需要一样的名字。
	2. client node ip 为10.13.132.225，配置如下:
		
			cluster.name: suli-elasticsearch
			node.name: node-2
			node.master: true
			node.data: flase
			network.host: 10.13.132.225
			discovery.zen.ping.unicast.hosts: ["10.13.132.225"]
			discovery.zen.ping.multicast.enabled: true
			
	3. data node ip 为10.13.132.209，配置如下:
			
			cluster.name: suli-elasticsearch
			node.name: node-3
			node.master: flase
			node.data: flase
			network.host: 10.13.132.209
			discovery.zen.ping.unicast.hosts: ["10.13.132.209"]
			discovery.zen.ping.multicast.enabled: true
			
* 节点启动
 	
 	1. 首先启动master节点，等到节点完全启动后，再依次启动剩下的两个节点，由于elasticsearch自带节点发现功能，启动的子节点会自动加入到集群中。
 	2. 验证节点是否加入集群中，向集群任意节点发送以下http请求：
 		
 			http://10.13.132.205:9200/_cluster/health
 		
 		正常回复节点状态如下：
 			
			{
			    "cluster_name": "suli-elasticsearch",
			    "status": "green",
			    "timed_out": false,
			    "number_of_nodes": 3,
			    "number_of_data_nodes": 3,
			    "active_primary_shards": 5,
			    "active_shards": 10,
			    "relocating_shards": 0,
			    "initializing_shards": 0,
			    "unassigned_shards": 0,
			    "delayed_unassigned_shards": 0,
			    "number_of_pending_tasks": 0,
			    "number_of_in_flight_fetch": 0,
			    "task_max_waiting_in_queue_millis": 0,
			    "active_shards_percent_as_number": 100
			}
			
 	可以看到当集群有三个节点，至此集群的简单部署已经完成了。
	
	
		
		
		

  