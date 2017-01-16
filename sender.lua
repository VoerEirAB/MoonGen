--
-- Created by Ashok Kumar (ashok@voereir.com).
-- User: ashok
-- Date: 13/01/17
-- Time: 4:10 PM
--

local mg     = require "moongen"
local memory = require "memory"
local device = require "device"
local stats  = require "stats"
local dpdk   = require "dpdk"
local log    = require "log"
local filter	= require "filter"
local timer	= require "timer"

local PKT_SIZE	= 64
local RUN_TIME_IN_SEC = 60
local NR_FLOWS = 1
local TX_QUEUES_PER_DEV = 1
local RX_QUEUES_PER_DEV = 1
local DST_MAC = ""
local LINE_RATE = 10000000000 -- 10Gbps

function master(...)
	local devices = { ... }
	if #devices == 0 then
		return print("Usage: port[:numcores] [port:[numcores] ...]")
	end
	local testParams = getTestParams()
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
		devices[i] = { device.config{ port = id, txQueues = testParams.txQueuesPerDev}, cores }
	end
	device.waitForLinks()
	for i, dev in ipairs(devices) do
		local dev, cores = unpack(dev)
		for i = 1, cores do
			print("starting on queue#%d" .. tostring(i - 1))
			mg.startTask("loadSlave", dev, dev:getTxQueue(i - 1), testParams)
		end
	end
	mg.waitForTasks()
end


function loadSlave(dev, queue, testParams)
	queue:setRateMpps(4)
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = queue,
			ethDst = testParams.dstMac,
			ip4Dst = "10.13.37.1",
			udpSrc = 1234,
			udpDst = 5678,
		}
	end)
	bufs = mem:bufArray(128)
	local baseIP = parseIPAddress("10.0.42.1")
	local flow = 0
	local ctr = stats:newDevTxCounter(dev, "plain")
	local runtime = timer:new(testParams.runTimeInSec)
	while (runTime == 0 or runtime:running()) and mg.running() do
		bufs:alloc(testParams.pktSize - 4) -- Without CRC header.
		for _, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.ip4.src:set(baseIP + flow)
			flow = incAndWrap(flow, testParams.numFlows)
		end
		-- UDP checksums are optional, so just IP checksums are sufficient here
		bufs:offloadIPChecksums()
		dev:setRate(testParams.startRate)
		queue:send(bufs)
		ctr:update(0.5)
	end
    	bufs:freeAll()
	ctr:finalize()
	dev:getStats()
end

function getTestParams(testParams)
	filename = "moongen-cfg.lua"
	local cfg
	if fileExists(filename) then
		log:info("reading [%s]", filename)
		cfgScript = loadfile(filename)
		setfenv(cfgScript, setmetatable({ TOUCHSTONE = function(arg) cfg = arg end }, { __index = _G }))
		local ok, err = pcall(cfgScript)
		if not ok then
			log:error("Could not load DPDK config: " .. err)
			return false
		end
		if not cfg then
			log:error("Config file does not contain VSPERF statement")
			return false
		end
	else
		log:warn("No %s file found, using defaults", filename)
	end
	local testParams = cfg or {}
	testParams.pktSize = testParams.pktSize or PKT_SIZE
	local max_line_rate_Mfps = (LINE_RATE /(testParams.pktSize*8 +64 +96) /1000000) --max_line_rate_Mfps is in millions per second
	--testParams.testType = testParams.testType or TEST_TYPE
	testParams.startRate = testParams.startRate or max_line_rate_Mfps
	--if testParams.startRate > max_line_rate_Mfps then
	--	log:warn("You have specified a packet rate that is greater than line rate.  This will probably not work");
	--end
	testParams.runTimeInSec = testParams.runTimeInSec or RUN_TIME_IN_SEC
	testParams.numFlows = testParams.numFlows or NR_FLOWS
	testParams.ports = testParams.ports or {0,1}
	testParams.flowMods = testParams.flowMods or {"srcIp"}
	testParams.txQueuesPerDev = testParams.txQueuesPerDev or TX_QUEUES_PER_DEV
	testParams.rxQueuesPerDev = testParams.rxQueuesPerDev or RX_QUEUES_PER_DEV
	testParams.srcIp = testParams.srcIp or SRC_IP
	testParams.dstIp = testParams.dstIp or DST_IP
	--testParams.srcPort = testParams.srcPort or SRC_PORT
	--testParams.dstPort = testParams.dstPort or DST_PORT
	--testParams.srcMac = testParams.srcMac or SRC_MAC
	testParams.dstMac = testParams.dstMac or DST_MAC
	--testParams.vlanId = testParams.vlanId
	testParams.baseDstMacUnsigned = macToU48(testParams.dstMac)
	--testParams.baseSrcMacUnsigned = macToU48(testParams.srcMac)
	--testParams.srcIp = parseIPAddress(testParams.srcIp)
	testParams.dstIp = parseIPAddress(testParams.dstIp)
	--testParams.oneShot = testParams.oneShot or false
	return testParams
end
function fileExists(f)
	local file = io.open(f, "r")
	if file then
	file:close()
	end
	return not not file
end

function macToU48(mac)
	-- this is similar to parseMac, but maintains ordering as represented in the input string
	local bytes = {string.match(mac, '(%x+)[-:](%x+)[-:](%x+)[-:](%x+)[-:](%x+)[-:](%x+)')}
	if bytes == nil then
	return
	end
	for i = 1, 6 do
	if bytes[i] == nil then
			return
		end
		bytes[i] = tonumber(bytes[i], 16)
		if  bytes[i] < 0 or bytes[i] > 0xFF then
			return
		end
	end
	local acc = 0
	for i = 1, 6 do
		acc = acc + bytes[i] * 256 ^ (6 - i)
	end
	return acc
end
