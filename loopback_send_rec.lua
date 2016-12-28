local mg     = require "moongen"
local memory = require "memory"
local device = require "device"
local stats  = require "stats"
local log    = require "log"
local PKT_SIZE	= 60

function master(...)
	local devices = { ... }
	local sender_dev
	local rec_dev
	if #devices == 0 then
		return print("Usage: port[:numcores] [port:[numcores] ...]")
	end
	for i, v in ipairs(devices) do
		local id, cores
		if type(v) == "string" then
			id, cores = tonumberall(v:match("(%d+):(%d+)"))
		else
			id, cores = v, 1
		end
		if not id or not cores then
			print("could not parse " .. tostring(v))
			return
		end
                if i == 1 then
                        log:info("Starting sender devices")
			sender_dev = device.config{ port = i - 1, txQueues = 1 }
		else
			log:info("Starting reciever devices")
			rec_dev = device.config{ port = i - 1, rxQueues = 1 }
		end
	end
	device.waitForLinks()
	mg.startTask("loadSlave", sender_dev, rec_dev, sender_dev:getTxQueue(0), 256, false)
	mg.startTask("counterSlave", rec_dev:getRxQueue(0))
	mg.waitForTasks()
end


function loadSlave(dev, rec_dev, queue, numFlows, showStats)
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = queue,
			ethDst = rec_dev:getMacString(),
			ip4Dst = "192.168.11.0",
			udpSrc = 1234,
			udpDst = 5678,	
		}
	end)
	bufs = mem:bufArray(128)
	local baseIP = parseIPAddress("192.168.111.20")
	local flow = 0
	local ctr = stats:newDevTxCounter(dev, "plain")
	while mg.running() do
		bufs:alloc(PKT_SIZE)
		for _, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.ip4.src:set(baseIP + flow)
			flow = incAndWrap(flow, numFlows)
		end
		-- UDP checksums are optional, so just IP checksums are sufficient here
		bufs:offloadIPChecksums()
		queue:send(bufs)
		if showStats then ctr:update() end
	end
	if showStats then ctr:finalize() end
end

function counterSlave(queue)
        -- the simplest way to count packets is by receiving them all
        -- an alternative would be using flow director to filter packets by port and use the queue statistics
        -- however, the current implementation is limited to filtering timestamp packets
        -- (changing this wouldn't be too complicated, have a look at filter.lua if you want to implement this)
        -- however, queue statistics are also not yet implemented and the DPDK abstraction is somewhat annoying
        local bufs = memory.bufArray()
        local ctrs = {}
        while mg.running(100) do
                local rx = queue:recv(bufs)
                for i = 1, rx do
                        local buf = bufs[i]
                        local pkt = buf:getUdpPacket()
                        local port = pkt.udp:getDstPort()
                        local ctr = ctrs[port]
                        if not ctr then
                                ctr = stats:newPktRxCounter("Port " .. port, "plain")
                                ctrs[port] = ctr
                        end
                        ctr:countPacket(buf)
                end
                -- update() on rxPktCounters must be called to print statistics periodically
                -- this is not done in countPacket() for performance reasons (needs to check timestamps)
                for k, v in pairs(ctrs) do
                        v:update()
                end
                bufs:freeAll()
        end
        for k, v in pairs(ctrs) do
                v:finalize()
        end
        -- TODO: check the queue's overflow counter to detect lost packets
end
