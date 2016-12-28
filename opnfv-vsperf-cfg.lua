VSPERF {
	startRate = 5,
        testType = "throughput",
	runBidirec = false,
	ports = {0,0},
        srcIp = "192.168.111.20",
        dstIp = "192.168.111.25",
        dstMac = "fa:16:3e:b1:28:bf",
        txQueuesPerDev = 1,
        rxQueuesPerDev = 1, 
        oneShot = true
   }
