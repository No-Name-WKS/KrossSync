--[[  LICENSE
--------------------------------------------------------------------------------
MIT License

Copyright (c) 2026 NoName-wks

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--------------------------------------------------------------------------------
]]

--[[ README
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
]]

-----------values(plsChange)---------

local AUTO_SAVE_TIME = 300 --(Second) Save Data,Memory

------------------------------------

type StateType = "NotReady" | "NoInternet" | "NoAccess" | "Access" | "Error"
type State = {Total: StateType, Data: StateType, Memory: StateType, Message: StateType}

type KrossSyncMetatablesType<MemoryTemplate,DataTemplat> = {[string]: {[string]:KrossSync<MemoryTemplate,DataTemplat>} | nil}

type Data<MemoryTemplate,DataTemplate> = {
	lastUpdate: number,
	dataCreateTime: number,
	memory: MemoryTemplate,
	data: DataTemplate,
}
type KrossSync<MemoryTemplate,DataTemplate> = {
	Store: DataStore,
	Map: MemoryStoreHashMap,
	SyncKey: string?,
	DataTemplate: DataTemplate,
	MemoryTemplate: MemoryTemplate,
	Data: Data<MemoryTemplate,DataTemplate>,
	LastData: Data<MemoryTemplate,DataTemplate>,
	IsSynced: boolean,
	----.signal----
	OnNewData: signal.Signal<string, Data<MemoryTemplate,DataTemplate> >,
	OnSync: signal.Signal<nil>,

}

local error = function(str,lvl) error(`||{script.Name}|| {tostring(str)}`,lvl) end
local warn = function(str) warn(`||{script.Name}|| {tostring(str)}`) end
local print = function(str) print(`||{script.Name}|| {tostring(str)}`) end


local signal = require(game.ReplicatedStorage.scr.Library.Signal) --Signal+ by Alexander Lindholt (MIT License)  -----https://github.com/AlexanderLindholt/SignalPlus  | v3.7.2

local State = {Total= "NotReady", Data= "NotReady", memory= "NotReady", Message= "NotReady"}
local IsCritical = {Data = false,Memory = false,Message = false}
local IsOverwrite = {Data = false,Memory = false,Message = false}

--Signal | ManyErrors | (IsCritical, KrossSyncService.IsCritical)
local OnCritcalToggle = signal()::signal.Signal<boolean,typeof(IsCritical)>
--Signal | Error. | (Where[1=Data,2=Memory,3=Message], ErrorMessage, Store_Or_Map_Name, Key, Data_Or_Func)
local OnError  = signal()::signal.Signal<number,string,string,string,any>
--Signal | TYPE BROKEN | (Where[1=Data,2=Memory,3=Message], Store_Or_Map_Name, Key, Data_Or_Func)
local OnOverwrite = signal()::signal.Signal<number,string,string,string> 


local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local MemeoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")




local Queue = require(game.ReplicatedStorage.scr.Library.Queue)


--[[ 
maxRetries: 최대 재시도 횟수(기본4, 최소2)
action: 실행할 함수 *acction(value[?])*  {action:func, value:table} 
failedMessage: 실패 시 출력할 메시지
AllFailedMessage: 실패 시 출력할 경고 메시지
----------------------------------------
return 성공 여부, 결과 or 에러 
]]--TODO: Make It Work
local function ExponentialJitterBackoff( 
	maxRetries:number?, action:{action:(...any)->any,value:{any}?},
	failedMessage:string, AllFailedMessage:string 
): (boolean,any)

	if (not maxRetries) or maxRetries < 2 then
		maxRetries = 2
		warn("[ExponentialJitterBackoff] maxRetries가 2 미만으로 설정되었습니다. 최소값 2로 설정됩니다.",action)
	end


	if not action or not action.action then
		warn("[ExponentialJitterBackoff] action.action 이 `nil` 입니다")
		return false, "action is nil"
	end

	local attempt = 0
	local success = false
	local result = nil



	while attempt < maxRetries do
		success, result = pcall(function()
			return action.action(unpack(action.value or {}))
		end)

		if success then
			return true, result
		else
			attempt += 1

			local base = math.pow(2, attempt)
			local waitTime = base + (math.random() * base)

			local msg = failedMessage or "[retryWithBackoff] failed"
			print(`{msg} | 시도: {attempt}/{maxRetries} | 대기: {string.format("%.2f", waitTime)}초 | 에러: {result}`)

			if attempt < maxRetries then
				task.wait(waitTime)
			end
		end
	end
	local msg = AllFailedMessage or failedMessage or "" 
	warn(`[ExponentialJitterBackoff] ALL failed | attempt: {attempt} | {msg} | error: {result} | `)
	return false, result 
end

local function DeepCopyTable(t)
	local copy = {}
	for key, value in pairs(t) do
		if type(value) == "table" then
			copy[key] = DeepCopyTable(value)
		else
			copy[key] = value
		end
	end
	return copy
end

local function ReconcileTable(target, template)
	for k, v in pairs(template) do
		if type(k) == "string" then -- Only string keys will be reconciled
			if target[k] == nil then
				if type(v) == "table" then
					target[k] = DeepCopyTable(v)
				else
					target[k] = v
				end
			elseif type(target[k]) == "table" and type(v) == "table" then
				ReconcileTable(target[k], v)
			end
		end
	end
end

local function GetData(self:KrossSync<any,any>,DataStore:DataStore,key:string): ...any

end


-------------------------------------------------------------------MODULE-------------------------------------


local KrossSyncMetables={}

local KrossSync = {} do
	KrossSync.__index = KrossSync

	-----------------------.value------------------------
	KrossSync.Store = nil
	KrossSync.Map = nil
	KrossSync.SyncKey = nil
	KrossSync.DataTemplate = nil
	KrossSync.MemoryTemplate = nil
	KrossSync.Data = nil
	KrossSync.Memory = nil
	KrossSync.LastData = nil
	KrossSync.IsSynced = false
	----.signal----

	--Signal|| (key, LastData, Data)
	KrossSync.OnNewData = signal()
	--Signal|| ()
	KrossSync.OnSync = signal()

	-----------------------.function---------------------



	-----------------------:function----------------------



	function KrossSync:Get(key) 

	end

	function KrossSync:Set(key,data,expiration)

	end

	function KrossSync:Update(key,func,expiration)

	end

	------------------------------------------------------

	function KrossSync:GetData(key)

	end

	function KrossSync:SetData(key,data)

	end

	function KrossSync:UpdateData(key,func)

	end


	------------------------------------------------------

	function KrossSync:GetMemory(key)

	end

	function KrossSync:SetMemory(key,data)

	end

	function KrossSync:UpdateMemory(key,func)

	end

	------------------------------------------------------

	function KrossSync:SendMessage(key,Data)

	end

	------------------------------------------------------

	function KrossSync:Sync() -- :DeSync

		do
			local DeSync = {}
			function DeSync:DeSync()

			end
			return DeSync
		end
	end

	function KrossSync:Offline()

	end

	--[[------------------------------------------------]]end
------------------------------------------------------

type KrossSyncService = {
	State: State,
	IsCritical: typeof(IsCritical),
	IsOverwrite: typeof(IsOverwrite)
}

local KrossSyncService:KrossSyncService = {}


-----------------------.value------------------------

--"NotReady", "NoInternet", "NoAccess", "Access", "Error"
KrossSyncService.State = State
KrossSyncService.IsCritical = IsCritical
KrossSyncService.IsOverwrite = IsOverwrite

----.signal----

--Signal | ManyErrors | (IsCritical, KrossSyncService.IsCritical)
KrossSyncService.OnCritcalToggle = OnCritcalToggle
--Signal | Error. | (Where[1=Data,2=Memory,3=Message], ErrorMessage, Store_Or_Map_Name, Key, Data_Or_Func)
KrossSyncService.OnError  = OnError
--Signal | TYPE BROKEN | (Where[1=Data,2=Memory,3=Message], Store_Or_Map_Name, Key, Data_Or_Func)
KrossSyncService.OnOverwrite = OnOverwrite

-----------------------.function---------------------

--TODO_ Store_Map_Name 변수명 바꾸기
function KrossSyncService.get(StoreName,SyncKey,DataTemplate,MemoryTemplate)

	if not(SyncKey == nil or SyncKey == "") and 
		(KrossSyncMetables[SyncKey] and 
			KrossSyncMetables[SyncKey].DataTemplate == DataTemplate and 
			KrossSyncMetables[SyncKey].MemoryTemplate == MemoryTemplate and 
			KrossSyncMetables[SyncKey].Store.Name == StoreName) then

		return KrossSyncMetables[SyncKey], true
	end

	local self = setmetatable({},KrossSync)::KrossSync<typeof(DataTemplate),typeof(MemoryTemplate)>
	self.Store = DataStoreService:GetDataStore(StoreName)
	self.Map = MemeoryStoreService:GetHashMap(StoreName)
	self.DataTemplate = DataTemplate
	self.MemoryTemplate = MemoryTemplate
	self.SyncKey = SyncKey
	

	if SyncKey == nil or SyncKey == "" then
		--(for debug?) KrossSyncMetables[#KrossSyncMetables+1] = self
		return self
	else
		KrossSyncMetables[SyncKey] = self
		return KrossSyncMetables[SyncKey], true
	end

end
-----------------------:function---------------------

--*FreezedTable* LOW EFFIECIENCY
function KrossSyncService:SeeKrossSync(SyncKey)
	if (SyncKey and typeof(SyncKey) == "string") and KrossSyncMetables[SyncKey] then
		return table.freeze(DeepCopyTable(KrossSyncMetables[SyncKey]))
	else
		return nil
	end

end
-----------------------NotModule---------------------

