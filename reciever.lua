--
-- Created by Ashok kumar (ashok@voereir.com).
-- User: ashok
-- Date: 13/01/17
-- Time: 4:13 PM
-- To change this template use File | Settings | File Templates.
--

--- This script is simple receiver of packets on dpdk NIC(s).
local mg        = require "moongen"
local memory    = require "memory"
local device    = require "device"
local ts        = require "timestamping"
local filter    = require "filter"
local stats     = require "stats"
local timer     = require "timer"
local log       = require "log"
local RUN_TIME_IN_SEC = 60

function master(...)
        local devices = { ... }
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
                devices[i] = { device.config{ port = id, txQueues = 1, rxQueues = cores }, cores }
        end
        device.waitForLinks()
        for i, dev in ipairs(devices) do
                local dev, cores = unpack(dev)
                for i = 1, cores do
			print("starting on queue#" .. tostring(i - 1))
			--dev:l2Filter(i , dev:getRxQueue(i - 1))
			--dev:fiveTupleFilter( { dstIp = "10.13.37.1" } , dev:getRxQueue(i - 1))
                        mg.startTask("counterSlave", dev:getRxQueue(i - 1))
                end
        end
        mg.waitForTasks()
end

function counterSlave(queue)
        -- the simplest way to count packets is by receiving them all
        -- an alternative would be using flow director to filter packets by port and use the queue statistics
        -- however, the current implementation is limited to filtering timestamp packets
        -- (changing this wouldn't be too complicated, have a look at filter.lua if you want to implement this)
        -- however, queue statistics are also not yet implemented and the DPDK abstraction is somewhat annoying
        local bufs = memory.bufArray(256)
        local ctrs = {}
        local runtime = timer:new(RUN_TIME_IN_SEC)
	    while (runTime == 0 or runtime:running()) and mg.running() do
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