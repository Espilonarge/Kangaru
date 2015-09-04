function buildTradingConfig()
  -- Build list of all possible items
  local level = entity.level()
  local items = {}
  self.merchantPools = root.assetJson(entity.configParameter("merchant.poolsFile", "/npcs/merchantpools.config"))
  for _, category in pairs(getCategories()) do
    local levelSets = self.merchantPools[category]
    if levelSets ~= nil then
      -- Find the highest available level within the category
      local highestLevel, highestLevelSet = -1, nil
      for _, levelSet in pairs(levelSets) do
        if level >= levelSet[1] and levelSet[1] > highestLevel then
          highestLevel, highestLevelSet = levelSet[1], levelSet[2]
        end
      end

      if highestLevelSet ~= nil then
        for _, item in pairs(highestLevelSet) do
          if item.item.parameters then item.item.parameters.level = entity.level() end
          table.insert(items, item)
        end
      end
    end
  end

  -- Reset the PRNG so the same seed always generates the same set of items.
  -- The uint64_t seed can get truncated when converted to a lua double, but
  -- it will at least provide a deterministic seed, even if the full range of
  -- input seeds can't be used
  local seed = tonumber(entity.seed())
  math.randomseed(seed)

  -- Shuffle the list
  for i = #items, 2, -1 do
    local j = math.random(i)
    items[i], items[j] = items[j], items[i]
  end

  local selectedItems, skippedItems = {}, {}
  local numItems = entity.configParameter("merchant.numItems")
  for _, item in pairs(items) do
    if item.rarity == nil or math.random() < item.rarity then
      table.insert(selectedItems, item)

      if #selectedItems == numItems then
        break
      end
    else
      table.insert(skippedItems, item)
    end
  end

  -- May need to dip into the rare items to get enough
  for i = 1, math.min(#skippedItems, numItems - #selectedItems) do
    table.insert(selectedItems, skippedItems[i])
  end

  -- Generate all randomized items with a consistent seed and level
  local level = entity.level()
  for _, item in pairs(selectedItems) do
    if item.item.name ~= nil and string.find(item.item.name, "^generated") then
      if item.item.parameters then
        if item.item.parameters.level == nil then
          item.item.parameters.level = level
        end

        if item.item.parameters.seed == nil then
          item.item.parameters.seed = math.random() * seed
        end
      end
    end
  end

  -- If this is the first time, pick a randomized buyFactor and sellFactor
  if storage.buyFactor == nil then
    storage.buyFactor = entity.randomizeParameterRange("merchant.buyFactorRange")
  end
  if storage.sellFactor == nil then
    storage.sellFactor = entity.randomizeParameterRange("merchant.sellFactorRange")
  end

  -- Now build the actual trading config
  local tradingConfig = {
    config = "/interface/windowconfig/merchant.config",
    sellFactor = storage.sellFactor,
    buyFactor = storage.buyFactor,
    items = selectedItems,
    paneLayoutOverride = entity.configParameter("merchant.paneLayoutOverride", nil)
  }

  -- Reset RNG
  math.randomseed(os.time())

  return tradingConfig
end

function getCategories()
  local species = entity.species()
  world.logInfo("%s", sb.printJson(entity.configParameter("merchant.categories")))
  if entity.configParameter("merchant.categories.override") then
    return entity.configParameter("merchant.categories.override")
  elseif entity.configParameter("merchant.categories."..species) then
    return entity.configParameter("merchant.categories."..species)
  else
    return entity.configParameter("merchant.categories.default")
  end
end

function enableTrading(args, output)
  args = parseArgs(args, {})

  if not self.tradingConfig then
    self.tradingConfig = buildTradingConfig()
  end
  self.tradingEnabled = true
  return true
end