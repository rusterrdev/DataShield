local DataStoreService = game:GetService("DataStoreService")

local Promise = require(script.Promise)
local Signal = require(script.Signal)

local DataShield = {}
local Data = {}

local function resumeThreadDefer(thread: thread)
   task.defer(function()
        local s, _ = coroutine.resume(thread)
        if not s then task.spawn(thread) end
   end)
end

local function getDataStore(index: string)
    local runningThread = coroutine.running()

    local promise = Promise.new(function(resolve, reject, onCancel)
        local globalDataStore = DataStoreService:GetDataStore(index)
        
        if globalDataStore then resolve(globalDataStore) return globalDataStore end
        reject()
    end)
    local globalDataStore

    promise:andThen(function(_globalDataStore)
        resumeThreadDefer(runningThread)
        globalDataStore = _globalDataStore
        
    end):catch(function()
        resumeThreadDefer(runningThread)
        print("please, enable the API services to use this resource.")
    end)
    coroutine.yield()
    return globalDataStore
end



function DataShield.GetDataStoreAsync(
    dataStoreIndex: string,
    dataTemplate: {}
) : DataShieldClass
    local self = {
        _data_index = dataStoreIndex,
        _template = dataTemplate,
        globalDataStore = getDataStore(dataStoreIndex)
    }

    return setmetatable(self, {__index = Data, __mode = "k"})
end


function Data:LoadDataAsync(key: string): DataShield
    local runningThread = coroutine.running()

    local _dataHash = {}

    local promise = Promise.new(function(resolve, reject, onCancel)
        local data = self.globalDataStore:GetAsync(key)
        if data then resolve(data) return data end
        reject(self._template)
    end) 

    promise:andThen(function(data)
        _dataHash = {
            key = key,
            data = data,
            Released = Signal.new(),
            DataStore = self.globalDataStore,
            template = self._template
        }
        resumeThreadDefer(runningThread)
    end):catch(function(template)
        resumeThreadDefer(runningThread)
        _dataHash = {
            key = key,
            data = table.clone(template),
            Released = Signal.new(),
            DataStore = self.globalDataStore,
            template = self._template
        }
    end)
    
    coroutine.yield()
    return setmetatable(_dataHash, {__index = Data})
end

function Data:Release()
    local currentThread = coroutine.running()
    self.Released:Fire()

    local promise = Promise.new(function(resolve, reject, onCancel)
        self.DataStore:SetAsync(self.key, self.data)
        resolve()
    end)

    promise:andThen(function()
        resumeThreadDefer(currentThread)
        print("date saved successfully!")
    end)
    
    promise:catch(function()
        resumeThreadDefer(currentThread)
        print("occurred a error while saving this data.")
    end)

    coroutine.yield()
end

function Data:Reconcile()
    
    for dataIndex, dataValue in self.data do
        for templateDataIndex, templateDataValue in self.template do
            if not self.data[templateDataIndex] then self.data[templateDataIndex] = templateDataValue continue end

        end
    end
end

type _signal = typeof(Signal.new())

type DataShieldClass = {
    GetDataStoreAsync: () -> ShieldDataStore?
}

type ShieldDataStore = {
    LoadDataAsync: (self: ShieldDataStore & {}) -> DataShield?,
}

type DataShield = {
    Released: _signal,
    Release: (self: DataShield & {}) -> (),
    Reconcile: (self: DataShield & {}) -> (),

}

return DataShield
