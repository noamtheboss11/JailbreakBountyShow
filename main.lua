local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local UserInputService = game:GetService("UserInputService")

-- ==================== CONFIGURATION ====================
local GUI_SIZE = UDim2.fromOffset(850, 600)
local GUI_POS = UDim2.fromScale(0.5, 0.5)
local GUI_COLOR = Color3.fromRGB(25, 25, 30)
local ACCENT_COLOR = Color3.fromRGB(163, 162, 165)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local KEYBIND = Enum.KeyCode.X   -- Press L to toggle

-- ==================== GLOBAL VARIABLES ====================
local mainGui = nil
local mirrorScrollingFrame = nil
local cloneMap = {}
local activeConnections = {}

-- ==================== BOARD MIRRORING LOGIC ====================
local function syncProperties(original, clone)
    if original:IsA("Frame") or original:IsA("ImageLabel") or original:IsA("TextLabel") then
        clone.Size = original.Size
        clone.Position = original.Position
        clone.BackgroundColor3 = original.BackgroundColor3
        clone.BackgroundTransparency = original.BackgroundTransparency
        clone.BorderSizePixel = original.BorderSizePixel
        if original:IsA("TextLabel") then
            clone.Text = original.Text
            clone.TextColor3 = original.TextColor3
            clone.TextScaled = original.TextScaled
            clone.Font = original.Font
            clone.TextSize = original.TextSize
        elseif original:IsA("ImageLabel") then
            clone.Image = original.Image
            clone.ImageColor3 = original.ImageColor3
        end
    end
    for _, child in ipairs(original:GetChildren()) do
        local childClone = clone:FindFirstChild(child.Name)
        if childClone then
            syncProperties(child, childClone)
        end
    end
end

local function watchFrame(original, clone)
    local conn = original.Changed:Connect(function()
        if clone and clone.Parent then
            syncProperties(original, clone)
        else
            conn:Disconnect()
        end
    end)
    local descConn
    descConn = original.DescendantAdded:Connect(function(desc)
        if clone and clone.Parent then
            local newClone = desc:Clone()
            newClone.Parent = clone
            cloneMap[desc] = newClone
            syncProperties(desc, newClone)
            watchFrame(desc, newClone)
        end
    end)
    table.insert(activeConnections, conn)
    table.insert(activeConnections, descConn)
end

local function clearConnections()
    for _, conn in ipairs(activeConnections) do
        conn:Disconnect()
    end
    activeConnections = {}
end

local function findOriginalBoard()
    -- Method 1: MostWanted -> Board
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "MostWanted" then
            local board = obj:FindFirstChild("Board")
            if board and board:IsA("Frame") then return board end
        end
    end
    -- Method 2: UIListLayout parent
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("UIListLayout") and obj.Parent and obj.Parent:IsA("Frame") then
            return obj.Parent
        end
    end
    -- Method 3: structural
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Frame") then
            local hasList = false
            local frameCount = 0
            for _, child in ipairs(obj:GetChildren()) do
                if child:IsA("UIListLayout") then hasList = true end
                if child:IsA("Frame") then frameCount = frameCount + 1 end
            end
            if hasList and frameCount >= 2 then return obj end
        end
    end
    return nil
end

local function startMirroring(originalContainer, scrollingFrame)
    clearConnections()
    cloneMap = {}
    for _, child in ipairs(originalContainer:GetChildren()) do
        if child:IsA("Frame") then
            local clone = child:Clone()
            clone.Parent = scrollingFrame
            cloneMap[child] = clone
            syncProperties(child, clone)
            watchFrame(child, clone)
        end
    end
    local addedConn = originalContainer.ChildAdded:Connect(function(newChild)
        if newChild:IsA("Frame") then
            local newClone = newChild:Clone()
            newClone.Parent = scrollingFrame
            cloneMap[newChild] = newClone
            syncProperties(newChild, newClone)
            watchFrame(newChild, newClone)
        end
    end)
    table.insert(activeConnections, addedConn)
    local removedConn = originalContainer.ChildRemoved:Connect(function(removedChild)
        if cloneMap[removedChild] then
            cloneMap[removedChild]:Destroy()
            cloneMap[removedChild] = nil
        end
    end)
    table.insert(activeConnections, removedConn)
    local ancestryConn = originalContainer.AncestryChanged:Connect(function()
        if not originalContainer:IsDescendantOf(workspace) then
            if mainGui then mainGui:Destroy() end
            clearConnections()
            task.wait(1)
            setupAndRun()
        end
    end)
    table.insert(activeConnections, ancestryConn)
end

-- ==================== CREATE DRAGGABLE BOUNTY WINDOW ====================
local function createBountyWindow()
    if mainGui then mainGui:Destroy() end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BountyWindow"
    screenGui.Parent = PlayerGui
    screenGui.Enabled = false   -- start hidden
    
    -- Main frame (draggable)
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = GUI_SIZE
    mainFrame.Position = GUI_POS
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.BackgroundColor3 = GUI_COLOR
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui
    
    -- Top bar (for dragging + title + close)
    local topBar = Instance.new("Frame")
    topBar.Size = UDim2.new(1, 0, 0, 30)
    topBar.BackgroundColor3 = ACCENT_COLOR
    topBar.BorderSizePixel = 0
    topBar.Parent = mainFrame
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -30, 1, 0)
    title.BackgroundTransparency = 1
    title.Text = "BOUNTY BOARD"
    title.TextColor3 = TEXT_COLOR
    title.TextSize = 18
    title.Font = Enum.Font.GothamBold
    title.Parent = topBar
    
    -- Close button (hides the GUI)
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 1, 0)
    closeBtn.Position = UDim2.new(1, -30, 0, 0)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Text = "X"
    closeBtn.TextColor3 = TEXT_COLOR
    closeBtn.TextSize = 18
    closeBtn.Parent = topBar
    closeBtn.MouseButton1Click:Connect(function()
        screenGui.Enabled = false
    end)
    
    -- ScrollingFrame for bounty entries
    local bountyScrollingFrame = Instance.new("ScrollingFrame")
    bountyScrollingFrame.Size = UDim2.new(1, -10, 1, -40)
    bountyScrollingFrame.Position = UDim2.new(0, 5, 0, 35)
    bountyScrollingFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    bountyScrollingFrame.BorderSizePixel = 0
    bountyScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    bountyScrollingFrame.ScrollBarThickness = 6
    bountyScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    bountyScrollingFrame.Parent = mainFrame
    
    local uiListLayout = Instance.new("UIListLayout")
    uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    uiListLayout.Padding = UDim.new(0, 5)
    uiListLayout.Parent = bountyScrollingFrame
    
    -- Dragging logic
    local dragging = false
    local dragStart, startPos
    
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    topBar.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    mainGui = screenGui
    return bountyScrollingFrame
end

-- ==================== KEYBIND HANDLER ====================
local function setupKeybind()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == KEYBIND then
            if mainGui then
                mainGui.Enabled = not mainGui.Enabled
                if mainGui.Enabled then
                    -- Refresh board in case it changed while closed
                    local board = findOriginalBoard()
                    if board and mirrorScrollingFrame then
                        startMirroring(board, mirrorScrollingFrame)
                    end
                end
            end
        end
    end)
    print("Press " .. tostring(KEYBIND):gsub("Enum.KeyCode.", "") .. " to toggle bounty board")
end

-- ==================== MAIN SETUP ====================
local function setupAndRun()
    local originalBoard = findOriginalBoard()
    if not originalBoard then
        warn("Bounty board not found, retrying in 2 seconds...")
        task.wait(2)
        setupAndRun()
        return
    end
    
    print("Found original board:", originalBoard:GetFullName())
    mirrorScrollingFrame = createBountyWindow()
    startMirroring(originalBoard, mirrorScrollingFrame)
    setupKeybind()
end

setupAndRun()
