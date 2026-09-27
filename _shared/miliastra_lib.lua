-- ============================================================================
-- Lua 客户端 UI 脚本 API 声明文件
-- 本文件包含文档中的所有类型、枚举、全局函数和控件方法声明
-- 方法仅声明无需实现，但返回值类型正确
-- ============================================================================

---@meta miliastra_lib

-- ============================================================================
-- 枚举定义
-- ============================================================================

Enum = {}

-- Enum.EaseType
---@enum EaseType
Enum.EaseType = {
    Linear = nil,
    InSine = nil,
    OutSine = nil,
    InOutSine = nil,
    InQuad = nil,
    OutQuad = nil,
    InOutQuad = nil,
    InCubic = nil,
    OutCubic = nil,
    InOutCubic = nil,
    InQuart = nil,
    OutQuart = nil,
    InOutQuart = nil,
    InQuint = nil,
    OutQuint = nil,
    InOutQuint = nil,
    InExpo = nil,
    OutExpo = nil,
    InOutExpo = nil,
    InCirc = nil,
    OutCirc = nil,
    InOutCirc = nil,
    InBack = nil,
    OutBack = nil,
    InOutBack = nil,
    InElastic = nil,
    OutElastic = nil,
    InOutElastic = nil,
    InBounce = nil,
    OutBounce = nil,
    InOutBounce = nil
}

-- Enum.CustomVariableEntityType
---@enum CustomVariableEntityType
Enum.CustomVariableEntityType = {
    Level = nil,
    PlayerSelf = nil,
    AvatarSelf = nil
}

-- Enum.Device
---@enum Device
Enum.Device = {
    KeyboardAndMouse = nil,
    Mobile = nil,
    Controller = nil,
    MobileController = nil
}

-- Enum.StageMode
---@enum StageMode
Enum.StageMode = {
    Beyond = nil,
    Classic = nil
}

-- Enum.LanguageType
---@enum LanguageType
Enum.LanguageType = {
    LanguageNone = nil,
    LanguageEng = nil,
    LanguageChs = nil,
    LanguageCht = nil,
    LanguageFra = nil,
    LanguageDeu = nil,
    LanguageSpa = nil,
    LanguagePor = nil,
    LanguageRus = nil,
    LanguageJpn = nil,
    LanguageKor = nil,
    LanguageTha = nil,
    LanguageVie = nil,
    LanguageInd = nil,
    LanguageTur = nil,
    LanguageIta = nil
}

-- Enum.ParamType
---@enum ParamType
Enum.ParamType = {
    Entity = nil,
    EntityList = nil,
    Int = nil,
    IntList = nil,
    Bool = nil,
    BoolList = nil,
    Float = nil,
    FloatList = nil,
    String = nil,
    StringList = nil,
    Vector3 = nil,
    Vector3List = nil,
    Guid = nil,
    GuidList = nil,
    ConfigId = nil,
    PrefabId = nil,
    ConfigIdList = nil,
    PrefabIdList = nil
}

-- Enum.CursorEventType
---@enum CursorEventType
Enum.CursorEventType = {
    CursorDown = nil,
    CursorUp = nil,
    CursorEnter = nil,
    CursorExit = nil,
    CursorDrag = nil,
    CursorBeginDrag = nil,
    CursorEndDrag = nil,
    CursorClick = nil
}

-- Enum.ScrollDirection
---@enum ScrollDirection
Enum.ScrollDirection = {
    Horizontal = nil,
    Vertical = nil
}

-- Enum.ScrollLayoutConstraint
---@enum ScrollLayoutConstraint
Enum.ScrollLayoutConstraint = {
    AutoWrap = nil,
    Fixed = nil
}

-- Enum.ScrollAlignType
---@enum ScrollAlignType
Enum.ScrollAlignType = {
    Bottom = nil,
    Center = nil,
    Top = nil
}

-- Enum.ControllerNavigationDir
---@enum ControllerNavigationDir
Enum.ControllerNavigationDir = {
    Up = nil,
    Down = nil,
    Left = nil,
    Right = nil
}

-- Enum.ControllerNavigationEventType
---@enum ControllerNavigationEventType
Enum.ControllerNavigationEventType = {
    Confirm = nil,
    Cancel = nil,
    Focus = nil,
    LostFocus = nil,
    RightStickUp = nil,
    RightStickDown = nil,
    RightStickRight = nil,
    RightStickLeft = nil,
    LeftStickUp = nil,
    LeftStickDown = nil,
    LeftStickRight = nil,
    LeftStickLeft = nil
}

-- Enum.ControllerNavigationMode
---@enum ControllerNavigationMode
Enum.ControllerNavigationMode = {
    None = nil,
    NearestControl = nil,
    Specified = nil
}

-- Enum.TextHorizontalAlignment
---@enum TextHorizontalAlignment
Enum.TextHorizontalAlignment = {
    Left = nil,
    Middle = nil,
    Right = nil
}

-- Enum.TextVerticalAlignment
---@enum TextVerticalAlignment
Enum.TextVerticalAlignment = {
    Top = nil,
    Middle = nil,
    Bottom = nil
}

-- Enum.ImageType
---@enum ImageType
Enum.ImageType = {
    Basic = nil,
    Stretch = nil
}

-- Enum.ImageSource
---@enum ImageSource
Enum.ImageSource = {
    StaticReference = nil,
    Item = nil,
    Equipment = nil,
    Skill = nil,
    UnitStatus = nil,
    Faction = nil,
    Currency = nil,
    Prefab = nil
}

-- Enum.ImageFillType
---@enum ImageFillType
Enum.ImageFillType = {
    Unused = nil,
    Horizontal = nil,
    Vertical = nil,
    Radial90 = nil,
    Radial180 = nil,
    Radial360 = nil
}

-- Enum.ImageFillHorizontalType
---@enum ImageFillHorizontalType
Enum.ImageFillHorizontalType = {
    Left = nil,
    Right = nil
}

-- Enum.ImageFillVerticalType
---@enum ImageFillVerticalType
Enum.ImageFillVerticalType = {
    Bottom = nil,
    Top = nil
}

-- Enum.ImageFillRadial90Type
---@enum ImageFillRadial90Type
Enum.ImageFillRadial90Type = {
    BottomLeft = nil,
    TopLeft = nil,
    TopRight = nil,
    BottomRight = nil
}

-- Enum.ImageFillRadialType
---@enum ImageFillRadialType
Enum.ImageFillRadialType = {
    Bottom = nil,
    Left = nil,
    Top = nil,
    Right = nil
}

-- Enum.ImageMaskSoftEdgeMode
---@enum ImageMaskSoftEdgeMode
Enum.ImageMaskSoftEdgeMode = {
    Percentage = nil,
    Pixel = nil
}

-- Enum.UIAnimationLayer
---@enum UIAnimationLayer
Enum.UIAnimationLayer = {
    AboveAllControls = nil,
    BelowAllControls = nil
}

-- Enum.KeyboardKeyCode
---@enum KeyboardKeyCode
Enum.KeyboardKeyCode = {
    CraftspersonKey1 = nil,
    CraftspersonKey2 = nil,
    CraftspersonKey3 = nil,
    CraftspersonKey4 = nil,
    CraftspersonKey5 = nil,
    CraftspersonKey6 = nil,
    CraftspersonKey7 = nil,
    CraftspersonKey8 = nil,
    CraftspersonKey9 = nil,
    CraftspersonKey10 = nil,
    CraftspersonKey11 = nil,
    CraftspersonKey12 = nil,
    CraftspersonKey13 = nil,
    CraftspersonKey14 = nil,
    CraftspersonKey15 = nil,
    CraftspersonKey16 = nil,
    CraftspersonKey17 = nil,
    CraftspersonKey18 = nil,
    CraftspersonKey19 = nil,
    CraftspersonKey20 = nil,
    CraftspersonKey21 = nil,
    CraftspersonKey22 = nil,
    CraftspersonKey23 = nil,
    CraftspersonKey24 = nil,
    CraftspersonKey25 = nil,
    CraftspersonKey26 = nil,
    CraftspersonKey27 = nil,
    CraftspersonKey28 = nil,
    CraftspersonKey29 = nil,
    CraftspersonKey30 = nil,
    CraftspersonKey31 = nil,
    CraftspersonKey32 = nil,
    CraftspersonKey33 = nil,
    CraftspersonKey34 = nil,
    CraftspersonKey35 = nil,
    CraftspersonKey36 = nil,
    CraftspersonKey37 = nil,
    CraftspersonKey38 = nil,
    CraftspersonKey39 = nil,
    CraftspersonKey40 = nil,
    CraftspersonKey41 = nil,
    CraftspersonKey42 = nil,
    CraftspersonKey43 = nil,
    MoveForwardKey = nil,
    MoveBackwardKey = nil,
    MoveLeftKey = nil,
    MoveRightKey = nil,
    SwitchToWalkOrRunKey = nil,
    SprintKey = nil,
    JumpKey = nil,
    DropKey = nil,
    OpenShortcutWheelKey = nil,
    InteractKey = nil,
    NormalAttackKey = nil,
    CharacterSkill1Key = nil,
    CharacterSkill2Key = nil,
    CharacterSkill3Key = nil,
    CharacterSkill4Key = nil,
    None = nil
}

-- Enum.ControllerKeyCode
---@enum ControllerKeyCode
Enum.ControllerKeyCode = {
    CraftspersonKey1 = nil,
    CraftspersonKey2 = nil,
    CraftspersonKey3 = nil,
    CraftspersonKey4 = nil,
    CraftspersonKey5 = nil,
    CraftspersonKey6 = nil,
    CraftspersonKey7 = nil,
    CraftspersonKey8 = nil,
    CraftspersonKey9 = nil,
    CraftspersonKey10 = nil,
    CraftspersonKey11 = nil,
    CraftspersonKey12 = nil,
    CraftspersonKey13 = nil,
    CraftspersonKey14 = nil,
    SprintKey = nil,
    JumpKey = nil,
    InteractKey = nil,
    NormalAttackKey = nil,
    CharacterSkill1Key = nil,
    CharacterSkill2Key = nil,
    CharacterSkill3Key = nil,
    CharacterSkill4Key = nil,
    MenuConfirmKey = nil,
    MenuBackKey = nil,
    None = nil
}

-- Enum.KeyEventType
---@enum KeyEventType
Enum.KeyEventType = {
    -- 键盘按键按下
    KeyboardCraftspersonKey1Down = nil,
    KeyboardCraftspersonKey2Down = nil,
    KeyboardCraftspersonKey3Down = nil,
    KeyboardCraftspersonKey4Down = nil,
    KeyboardCraftspersonKey5Down = nil,
    KeyboardCraftspersonKey6Down = nil,
    KeyboardCraftspersonKey7Down = nil,
    KeyboardCraftspersonKey8Down = nil,
    KeyboardCraftspersonKey9Down = nil,
    KeyboardCraftspersonKey10Down = nil,
    KeyboardCraftspersonKey11Down = nil,
    KeyboardCraftspersonKey12Down = nil,
    KeyboardCraftspersonKey13Down = nil,
    KeyboardCraftspersonKey14Down = nil,
    KeyboardCraftspersonKey15Down = nil,
    KeyboardCraftspersonKey16Down = nil,
    KeyboardCraftspersonKey17Down = nil,
    KeyboardCraftspersonKey18Down = nil,
    KeyboardCraftspersonKey19Down = nil,
    KeyboardCraftspersonKey20Down = nil,
    KeyboardCraftspersonKey21Down = nil,
    KeyboardCraftspersonKey22Down = nil,
    KeyboardCraftspersonKey23Down = nil,
    KeyboardCraftspersonKey24Down = nil,
    KeyboardCraftspersonKey25Down = nil,
    KeyboardCraftspersonKey26Down = nil,
    KeyboardCraftspersonKey27Down = nil,
    KeyboardCraftspersonKey28Down = nil,
    KeyboardCraftspersonKey29Down = nil,
    KeyboardCraftspersonKey30Down = nil,
    KeyboardCraftspersonKey31Down = nil,
    KeyboardCraftspersonKey32Down = nil,
    KeyboardCraftspersonKey33Down = nil,
    KeyboardCraftspersonKey34Down = nil,
    KeyboardCraftspersonKey35Down = nil,
    KeyboardCraftspersonKey36Down = nil,
    KeyboardCraftspersonKey37Down = nil,
    KeyboardCraftspersonKey38Down = nil,
    KeyboardCraftspersonKey39Down = nil,
    KeyboardCraftspersonKey40Down = nil,
    KeyboardCraftspersonKey41Down = nil,
    KeyboardCraftspersonKey42Down = nil,
    KeyboardCraftspersonKey43Down = nil,
    KeyboardMoveForwardKeyDown = nil,
    KeyboardMoveBackwardKeyDown = nil,
    KeyboardMoveLeftKeyDown = nil,
    KeyboardMoveRightKeyDown = nil,
    KeyboardSwitchToWalkOrRunKeyDown = nil,
    KeyboardSprintKeyDown = nil,
    KeyboardJumpKeyDown = nil,
    KeyboardDropKeyDown = nil,
    KeyboardOpenShortcutWheelKeyDown = nil,
    KeyboardInteractKeyDown = nil,
    KeyboardNormalAttackKeyDown = nil,
    KeyboardCharacterSkill1KeyDown = nil,
    KeyboardCharacterSkill2KeyDown = nil,
    KeyboardCharacterSkill3KeyDown = nil,
    KeyboardCharacterSkill4KeyDown = nil,
    -- 键盘按键抬起
    KeyboardCraftspersonKey1Up = nil,
    KeyboardCraftspersonKey2Up = nil,
    KeyboardCraftspersonKey3Up = nil,
    KeyboardCraftspersonKey4Up = nil,
    KeyboardCraftspersonKey5Up = nil,
    KeyboardCraftspersonKey6Up = nil,
    KeyboardCraftspersonKey7Up = nil,
    KeyboardCraftspersonKey8Up = nil,
    KeyboardCraftspersonKey9Up = nil,
    KeyboardCraftspersonKey10Up = nil,
    KeyboardCraftspersonKey11Up = nil,
    KeyboardCraftspersonKey12Up = nil,
    KeyboardCraftspersonKey13Up = nil,
    KeyboardCraftspersonKey14Up = nil,
    KeyboardCraftspersonKey15Up = nil,
    KeyboardCraftspersonKey16Up = nil,
    KeyboardCraftspersonKey17Up = nil,
    KeyboardCraftspersonKey18Up = nil,
    KeyboardCraftspersonKey19Up = nil,
    KeyboardCraftspersonKey20Up = nil,
    KeyboardCraftspersonKey21Up = nil,
    KeyboardCraftspersonKey22Up = nil,
    KeyboardCraftspersonKey23Up = nil,
    KeyboardCraftspersonKey24Up = nil,
    KeyboardCraftspersonKey25Up = nil,
    KeyboardCraftspersonKey26Up = nil,
    KeyboardCraftspersonKey27Up = nil,
    KeyboardCraftspersonKey28Up = nil,
    KeyboardCraftspersonKey29Up = nil,
    KeyboardCraftspersonKey30Up = nil,
    KeyboardCraftspersonKey31Up = nil,
    KeyboardCraftspersonKey32Up = nil,
    KeyboardCraftspersonKey33Up = nil,
    KeyboardCraftspersonKey34Up = nil,
    KeyboardCraftspersonKey35Up = nil,
    KeyboardCraftspersonKey36Up = nil,
    KeyboardCraftspersonKey37Up = nil,
    KeyboardCraftspersonKey38Up = nil,
    KeyboardCraftspersonKey39Up = nil,
    KeyboardCraftspersonKey40Up = nil,
    KeyboardCraftspersonKey41Up = nil,
    KeyboardCraftspersonKey42Up = nil,
    KeyboardCraftspersonKey43Up = nil,
    KeyboardMoveForwardKeyUp = nil,
    KeyboardMoveBackwardKeyUp = nil,
    KeyboardMoveLeftKeyUp = nil,
    KeyboardMoveRightKeyUp = nil,
    KeyboardSwitchToWalkOrRunKeyUp = nil,
    KeyboardSprintKeyUp = nil,
    KeyboardJumpKeyUp = nil,
    KeyboardDropKeyUp = nil,
    KeyboardOpenShortcutWheelKeyUp = nil,
    KeyboardInteractKeyUp = nil,
    KeyboardNormalAttackKeyUp = nil,
    KeyboardCharacterSkill1KeyUp = nil,
    KeyboardCharacterSkill2KeyUp = nil,
    KeyboardCharacterSkill3KeyUp = nil,
    KeyboardCharacterSkill4KeyUp = nil,
    -- 手柄按键按下
    ControllerCraftspersonKey1Down = nil,
    ControllerCraftspersonKey2Down = nil,
    ControllerCraftspersonKey3Down = nil,
    ControllerCraftspersonKey4Down = nil,
    ControllerCraftspersonKey5Down = nil,
    ControllerCraftspersonKey6Down = nil,
    ControllerCraftspersonKey7Down = nil,
    ControllerCraftspersonKey8Down = nil,
    ControllerCraftspersonKey9Down = nil,
    ControllerCraftspersonKey10Down = nil,
    ControllerCraftspersonKey11Down = nil,
    ControllerCraftspersonKey12Down = nil,
    ControllerCraftspersonKey13Down = nil,
    ControllerCraftspersonKey14Down = nil,
    ControllerSprintKeyDown = nil,
    ControllerJumpKeyDown = nil,
    ControllerInteractKeyDown = nil,
    ControllerNormalAttackKeyDown = nil,
    ControllerCharacterSkill1KeyDown = nil,
    ControllerCharacterSkill2KeyDown = nil,
    ControllerCharacterSkill3KeyDown = nil,
    ControllerCharacterSkill4KeyDown = nil,
    ControllerMenuConfirmKeyDown = nil,
    ControllerMenuBackKeyDown = nil,
    -- 手柄按键抬起
    ControllerCraftspersonKey1Up = nil,
    ControllerCraftspersonKey2Up = nil,
    ControllerCraftspersonKey3Up = nil,
    ControllerCraftspersonKey4Up = nil,
    ControllerCraftspersonKey5Up = nil,
    ControllerCraftspersonKey6Up = nil,
    ControllerCraftspersonKey7Up = nil,
    ControllerCraftspersonKey8Up = nil,
    ControllerCraftspersonKey9Up = nil,
    ControllerCraftspersonKey10Up = nil,
    ControllerCraftspersonKey11Up = nil,
    ControllerCraftspersonKey12Up = nil,
    ControllerCraftspersonKey13Up = nil,
    ControllerCraftspersonKey14Up = nil,
    ControllerSprintKeyUp = nil,
    ControllerJumpKeyUp = nil,
    ControllerInteractKeyUp = nil,
    ControllerNormalAttackKeyUp = nil,
    ControllerCharacterSkill1KeyUp = nil,
    ControllerCharacterSkill2KeyUp = nil,
    ControllerCharacterSkill3KeyUp = nil,
    ControllerCharacterSkill4KeyUp = nil,
    ControllerMenuConfirmKeyUp = nil,
    ControllerMenuBackKeyUp = nil
}

-- ============================================================================
-- 全局函数
-- ============================================================================

--- 返回运行时类型
--- @param value any
--- @return string
function typeof(value) end

--- 将传入值写入普通日志
function print(...) end

--- 将传入值写入错误日志
function printerr(...) end

--- 生成并返回调用栈信息
--- @param message string|nil
--- @param level integer|nil
--- @return string
function debug.traceback(message, level) end

--- 将当前客户端控件树打印到日志
function game.PrintClientUITree() end

--- 判断数值是否为 NaN
--- @param n number
--- @return boolean
function math.isnan(n) end

--- 判断数值是否为无穷
--- @param n number
--- @return boolean
function math.isinf(n) end

-- ============================================================================
-- Color 类型
-- ============================================================================

--- @class ColorValue
---@overload fun(r:number, g:number, b:number, a:number?):ColorValue
Color = {}

--- 从 0-255 RGB 数值构造颜色
--- @param r number
--- @param g number
--- @param b number
--- @return ColorValue
function Color.FromRGB(r, g, b) end

--- 从 0-255 RGBA 数值构造颜色
--- @param r number
--- @param g number
--- @param b number
--- @param a number|nil
--- @return ColorValue
function Color.FromRGBA(r, g, b, a) end

--- 将 ColorValue 拆分为 RGBA 四通道
--- @param colorValue ColorValue
--- @return number, number, number, number
function Color.ToRGBA(colorValue) end

-- ============================================================================
-- Script 类型
-- ============================================================================

--- @class Script
--- @field alive boolean 脚本实例是否存活
--- @field id integer 脚本实例 ID
--- @field scriptMappingId integer 脚本映射 ID
--- @field object any 脚本绑定的运行时对象
--- @field path string 脚本路径
--- @field enabled boolean 脚本是否启用
script = {}

--- 按名称读取当前脚本参数
--- @param paramName string
--- @return any
function script:GetParam(paramName) end

--- 按名称调用当前脚本函数
--- @param funcName string
--- @param ... any
function script:Invoke(funcName, ...) end

--- 控制当前脚本的 Tick 开关
--- @param enabled boolean
function script:EnableUpdate(enabled) end

--- 注册服务器信号监听
--- @param signalName string 信号名称
--- @param callback fun(signalName: string, signalParams: any[])
function script:RegisterServerSignalHandler(signalName, callback) end

--- 移除指定名称的服务器信号监听
--- @param signalName string
function script:UnregisterServerSignalHandler(signalName) end

--- 监听全局自定义变量变化
--- @param entityType CustomVariableEntityType
--- @param customVariableName string
--- @param callback fun(entityType: CustomVariableEntityType, customVariableName: string)
function script:RegisterCustomVariableChangedHandler(entityType, customVariableName, callback) end

--- 移除指定实体类型和变量名的监听
--- @param entityType CustomVariableEntityType
--- @param customVariableName string
function script:UnregisterCustomVariableChangedHandler(entityType, customVariableName) end

-- ============================================================================
-- game 全局表
-- ============================================================================

game = {}

-- UI与层级

--- 根据已配置的 UI 元件 ID 创建控件实例
--- @param controlPrefabIndex integer
--- @param parent ClientUIBaseControl
--- @return ClientUIBaseControl
function game.InstantiateClientUIControl(controlPrefabIndex, parent) end

--- 销毁指定客户端控件
--- @param control ClientUIBaseControl
function game.DestroyClientUIControl(control) end

--- 按运行时客户端控件 ID 获取控件
--- @param controlId integer
--- @return ClientUIBaseControl
function game.GetClientUIControl(controlId) end

--- 按名称查找 UI 根控件
--- @param nodeName string
--- @return ClientUIBaseControl
function game.FindClientUIRoot(nodeName) end

--- 获取全部 UI 根控件
--- @return ClientUIBaseControl[]
function game.GetClientUIRoots() end

--- 获取 UI 画布宽高
--- @return number, number
function game.GetUICanvasSize() end

--- 获取光标 UI 坐标
--- @return number, number
function game.GetCursorUIPos() end

-- 输入与聚焦

--- 获取当前输入设备类型
--- @return Device
function game.GetDevice() end

--- 设置焦点当前聚焦控件
--- @param control ClientUIBaseControl
function game.SetControllerFocus(control) end

--- 获取当前聚焦控件
--- @return ClientUIBaseControl
function game.GetControllerFocus() end

--- 获取左摇杆轴值
--- @return number, number
function game.GetControllerLeftStickAxis() end

--- 获取右摇杆轴值
--- @return number, number
function game.GetControllerRightStickAxis() end

-- Tween、信号与自定义变量

--- 创建补间动画
--- @param object any
--- @param tweenDataTable table
--- @param duration number
--- @return Tween
function game.Tween(object, tweenDataTable, duration) end

--- 创建补间动画序列
--- @return TweenSequence
function game.TweenSequence() end

--- 按 signalName 创建服务器信号
--- @param signalName string
--- @return ServerSignal
function game.ServerSignal(signalName) end

--- 读取服务器指定实体的自定义变量值
--- @param entityType CustomVariableEntityType
--- @param customVariableName string
--- @return any
function game.GetGlobalCustomVariableValue(entityType, customVariableName) end

-- 关卡、音频与本地化

--- 暂停/恢复关卡时间
--- @param pause boolean
function game.PauseLevelTime(pause) end

--- 查询关卡时间是否暂停
--- @return boolean
function game.IsLevelTimePaused() end

--- 播放音效
--- @param audioId integer
--- @return integer
function game.PlayAudio2D(audioId) end

--- 停止指定音效实例
--- @param audioInstanceId integer
function game.StopAudio(audioInstanceId) end

--- 查询音效实例是否存活
--- @param audioInstanceId integer
--- @return boolean
function game.IsAudioAlive(audioInstanceId) end

--- 获取当前语言
--- @return LanguageType
function game.GetLanguageType() end

--- 获取当前关卡模式
--- @return StageMode
function game.GetStageMode() end

--- 查询当前是否处于测试播放状态
--- @return boolean
function game.IsTestPlay() end

--- 按已配置的文本 ID 获取本地化文本
--- @param textMapId string
--- @return string
function game.GetText(textMapId) end

-- ============================================================================
-- Tween 类型
-- ============================================================================

--- @class Tween
Tween = {}

--- 设置缓动类型
--- @param easeType EaseType
--- @return Tween
function Tween:SetEase(easeType) end

--- 设置目标值解释方式：false 为绝对值，true 为相对值
--- @param relative boolean
--- @return Tween
function Tween:SetRelative(relative) end

--- 开始播放
--- @return Tween
function Tween:Play() end

--- 暂停
function Tween:Pause() end

--- 从暂停处继续播放
function Tween:Resume() end

--- 回到开始状态并播放
function Tween:Restart() end

--- 立即切换到结束状态
function Tween:Complete() end

--- 销毁实例；complete 为 true 时触发完成回调，否则保持当前状态结束且不触发回调
--- @param complete boolean
function Tween:Kill(complete) end

--- 设置全部循环完成回调
--- @param onComplete fun()
--- @return Tween
function Tween:SetOnComplete(onComplete) end

--- 设置步骤完成回调
--- @param onStepComplete fun()
--- @return Tween
function Tween:SetOnStepComplete(onStepComplete) end

--- 设置循环次数；-1 表示无限循环
--- @param times integer
--- @return Tween
function Tween:SetLoops(times) end

-- ============================================================================
-- TweenSequence 类型
-- ============================================================================

--- @class TweenSequence
TweenSequence = {}

--- 在序列末尾接入 Tween
--- @param tween Tween
--- @return TweenSequence
function TweenSequence:Append(tween) end

--- 在序列末尾接入间隔
--- @param interval number
--- @return TweenSequence
function TweenSequence:AppendInterval(interval) end

--- 在序列末尾接入回调
--- @param callback fun()
--- @return TweenSequence
function TweenSequence:AppendCallback(callback) end

--- 与当前队尾步骤并行
--- @param tween Tween
--- @return TweenSequence
function TweenSequence:Join(tween) end

--- 在指定时间点插入 Tween
--- @param time number
--- @param tween Tween
--- @return TweenSequence
function TweenSequence:Insert(time, tween) end

--- 在指定时间点插入回调
--- @param time number
--- @param callback fun()
--- @return TweenSequence
function TweenSequence:InsertCallback(time, callback) end

--- 开始播放
--- @return TweenSequence
function TweenSequence:Play() end

--- 暂停序列
function TweenSequence:Pause() end

--- 继续播放序列
function TweenSequence:Resume() end

--- 回到初始状态并播放
function TweenSequence:Restart() end

--- 立即完成整个序列
function TweenSequence:Complete() end

--- 销毁序列；complete 为 true 时保持当前状态结束，否则不触发完成回调
--- @param complete boolean
function TweenSequence:Kill(complete) end

--- 设置整个序列完成回调
--- @param onComplete fun()
--- @return TweenSequence
function TweenSequence:SetOnComplete(onComplete) end

--- 设置步骤完成回调
--- @param onStepComplete fun()
--- @return TweenSequence
function TweenSequence:SetOnStepComplete(onStepComplete) end

--- 设置循环次数；-1 表示无限循环
--- @param times integer
--- @return TweenSequence
function TweenSequence:SetLoops(times) end

-- ============================================================================
-- ServerSignal 类型
-- ============================================================================

--- @class ServerSignal
ServerSignal = {}

--- 按显式类型添加参数
--- @param paramType ParamType
--- @param paramValue any
--- @return ServerSignal
function ServerSignal:AddParam(paramType, paramValue) end

--- 向服务器发送已添加的参数
function ServerSignal:SendSignal() end

--- 添加整数参数
--- @param intValue integer
--- @return ServerSignal
function ServerSignal:AddInt(intValue) end

--- 添加整数列表参数
--- @param intListValue integer[]
--- @return ServerSignal
function ServerSignal:AddIntList(intListValue) end

--- 添加浮点数参数
--- @param floatValue number
--- @return ServerSignal
function ServerSignal:AddFloat(floatValue) end

--- 添加浮点数列表参数
--- @param floatListValue number[]
--- @return ServerSignal
function ServerSignal:AddFloatList(floatListValue) end

--- 添加字符串参数
--- @param stringValue string
--- @return ServerSignal
function ServerSignal:AddString(stringValue) end

--- 添加字符串列表参数
--- @param stringListValue string[]
--- @return ServerSignal
function ServerSignal:AddStringList(stringListValue) end

--- 添加三维向量参数
--- @param vector3Value table
--- @return ServerSignal
function ServerSignal:AddVector3(vector3Value) end

--- 添加三维向量列表参数
--- @param vector3ListValue table[]
--- @return ServerSignal
function ServerSignal:AddVector3List(vector3ListValue) end

--- 添加布尔值参数
--- @param boolValue boolean
--- @return ServerSignal
function ServerSignal:AddBool(boolValue) end

--- 添加布尔值列表参数
--- @param boolListValue boolean[]
--- @return ServerSignal
function ServerSignal:AddBoolList(boolListValue) end

--- 添加 GUID 参数
--- @param guidValue integer
--- @return ServerSignal
function ServerSignal:AddGuid(guidValue) end

--- 添加 GUID 列表参数
--- @param guidListValue integer[]
--- @return ServerSignal
function ServerSignal:AddGuidList(guidListValue) end

--- 添加实体参数
--- @param entityValue integer
--- @return ServerSignal
function ServerSignal:AddEntity(entityValue) end

--- 添加实体列表参数
--- @param entityListValue integer[]
--- @return ServerSignal
function ServerSignal:AddEntityList(entityListValue) end

--- 添加元件 ID 参数
--- @param prefabIdValue integer
--- @return ServerSignal
function ServerSignal:AddPrefabId(prefabIdValue) end

--- 添加元件 ID 列表参数
--- @param prefabIdListValue integer[]
--- @return ServerSignal
function ServerSignal:AddPrefabIdList(prefabIdListValue) end

--- 添加配置 ID 参数
--- @param configIdValue integer
--- @return ServerSignal
function ServerSignal:AddConfigId(configIdValue) end

--- 添加配置 ID 列表参数
--- @param configIdListValue integer[]
--- @return ServerSignal
function ServerSignal:AddConfigIdList(configIdListValue) end

-- ============================================================================
-- ClientUIBaseControl 类型
-- ============================================================================

--- @class ClientUIBaseControl
--- @field alive boolean 只读；控件是否存活
--- @field id integer 只读；运行时客户端控件 ID
--- @field prefabIndex integer 只读；控件元件索引
--- @field active boolean 只读；控件自身是否激活
--- @field activeInHierarchy boolean 只读；控件在层级中是否激活
--- @field visible boolean 只读；控件是否可见
--- @field name string 读写；控件名称
--- @field parent ClientUIBaseControl 读写；父控件
--- @field anchoredPositionX number 读写、Tweenable；锚点位置 X
--- @field anchoredPositionY number 读写、Tweenable；锚点位置 Y
--- @field sizeDeltaX number 读写、Tweenable；尺寸差值 X
--- @field sizeDeltaY number 读写、Tweenable；尺寸差值 Y
--- @field anchorMinX number 读写、Tweenable；最小锚点 X
--- @field anchorMinY number 读写、Tweenable；最小锚点 Y
--- @field anchorMaxX number 读写、Tweenable；最大锚点 X
--- @field anchorMaxY number 读写、Tweenable；最大锚点 Y
--- @field pivotX number 读写、Tweenable；枢轴 X
--- @field pivotY number 读写、Tweenable；枢轴 Y
--- @field localScaleX number 读写、Tweenable；本地缩放 X
--- @field localScaleY number 读写、Tweenable；本地缩放 Y
--- @field localScaleZ number 读写、Tweenable；本地缩放 Z
--- @field localRotationX number 读写、Tweenable；本地旋转 X
--- @field localRotationY number 读写、Tweenable；本地旋转 Y
--- @field localRotationZ number 读写、Tweenable；本地旋转 Z
--- @field canControllerFocus boolean 读写；控件是否可被手柄聚焦
ClientUIBaseControl = {}

-- 层级操作

--- 获取直接子控件
--- @return ClientUIBaseControl[]
function ClientUIBaseControl:GetChildren() end

--- 按名称获取直接子控件
--- @param name string
--- @return ClientUIBaseControl
function ClientUIBaseControl:GetChild(name) end

--- 按路径查找子控件
--- @param path string
--- @return ClientUIBaseControl
function ClientUIBaseControl:FindChild(path) end

--- 设置激活状态；false 时会停止控件脚本逻辑
--- @param active boolean
function ClientUIBaseControl:SetActive(active) end

--- 仅设置可见性，不停止控件脚本逻辑
--- @param visible boolean
function ClientUIBaseControl:SetVisible(visible) end

--- 获取同级排序索引
--- @return integer
function ClientUIBaseControl:GetSiblingIndex() end

--- 设置同级排序索引；数值越大显示越靠后
--- @param index integer
--- @return boolean
function ClientUIBaseControl:SetSiblingIndex(index) end

--- 移到同级首位
--- @return boolean
function ClientUIBaseControl:SetAsFirstSibling() end

--- 移到同级末位
--- @return boolean
function ClientUIBaseControl:SetAsLastSibling() end

-- 布局与变换

--- 获取锚点位置
--- @return number, number
function ClientUIBaseControl:GetAnchoredPosition() end

--- 设置锚点位置
--- @param x number
--- @param y number
function ClientUIBaseControl:SetAnchoredPosition(x, y) end

--- 获取尺寸差值
--- @return number, number
function ClientUIBaseControl:GetSizeDelta() end

--- 设置尺寸差值
--- @param x number
--- @param y number
function ClientUIBaseControl:SetSizeDelta(x, y) end

--- 获取最小锚点
--- @return number, number
function ClientUIBaseControl:GetAnchorMin() end

--- 设置最小锚点
--- @param x number
--- @param y number
function ClientUIBaseControl:SetAnchorMin(x, y) end

--- 获取最大锚点
--- @return number, number
function ClientUIBaseControl:GetAnchorMax() end

--- 设置最大锚点
--- @param x number
--- @param y number
function ClientUIBaseControl:SetAnchorMax(x, y) end

--- 获取轴心
--- @return number, number
function ClientUIBaseControl:GetPivot() end

--- 设置轴心
--- @param x number
--- @param y number
function ClientUIBaseControl:SetPivot(x, y) end

--- 获取本地缩放
--- @return number, number, number
function ClientUIBaseControl:GetLocalScale() end

--- 设置本地缩放
--- @param x number
--- @param y number
--- @param z number
function ClientUIBaseControl:SetLocalScale(x, y, z) end

--- 获取本地旋转
--- @return number, number, number
function ClientUIBaseControl:GetLocalRotation() end

--- 设置本地旋转
--- @param x number
--- @param y number
--- @param z number
function ClientUIBaseControl:SetLocalRotation(x, y, z) end

-- 脚本访问

--- 按路径获取挂载脚本；返回对象可能因热重载或销毁失效，使用前检查 alive
--- @param scriptPath string
--- @return Script
function ClientUIBaseControl:GetScriptByPath(scriptPath) end

--- 按脚本元件 ID 获取挂载脚本；使用返回对象前检查 alive
--- @param scriptMappingId integer
--- @return Script
function ClientUIBaseControl:GetScript(scriptMappingId) end

--- 获取控件上全部脚本
--- @return Script[]
function ClientUIBaseControl:GetScripts() end

-- 键盘/手柄按键事件

--- 注册指定按键事件
--- @param eventType KeyEventType
--- @param callback fun()
function ClientUIBaseControl:AddKeyEventListener(eventType, callback) end

--- 移除指定事件和回调；callback 必须与注册时使用的引用相同
--- @param eventType KeyEventType
--- @param callback fun()
function ClientUIBaseControl:RemoveKeyEventListener(eventType, callback) end

--- 移除指定事件的全部监听
--- @param eventType KeyEventType
function ClientUIBaseControl:RemoveKeyEventListeners(eventType) end

--- 移除全部按键事件监听
function ClientUIBaseControl:RemoveAllKeyEventListeners() end

-- 手柄导航事件

--- 注册手柄导航事件
--- @param eventType ControllerNavigationEventType
--- @param callback fun()
function ClientUIBaseControl:AddNavigationEventListener(eventType, callback) end

--- 移除指定事件和回调；callback 必须与注册时使用的引用相同
--- @param eventType ControllerNavigationEventType
--- @param callback fun()
function ClientUIBaseControl:RemoveNavigationEventListener(eventType, callback) end

--- 移除指定导航事件的全部监听
--- @param eventType ControllerNavigationEventType
function ClientUIBaseControl:RemoveNavigationEventListeners(eventType) end

--- 移除全部导航事件监听
function ClientUIBaseControl:RemoveAllNavigationEventListeners() end

-- 手柄导航配置

--- 设置指定方向的导航目标；navigationTarget 可以为 nil
--- @param navigationDir ControllerNavigationDir
--- @param navigationMode ControllerNavigationMode
--- @param navigationTarget ClientUIBaseControl|nil
function ClientUIBaseControl:SetControllerNavigation(navigationDir, navigationMode, navigationTarget) end

--- 返回指定方向的导航配置
--- @param navigationDir ControllerNavigationDir
--- @return ControllerNavigationMode, ClientUIBaseControl|nil
function ClientUIBaseControl:GetControllerNavigation(navigationDir) end

-- ============================================================================
-- ClientUIImageControl 类型
-- ============================================================================

--- @class ClientUIImageControl : ClientUIBaseControl
--- @field imageSource ImageSource 只读；图片来源
--- @field imageId integer 只读；图片 ID
--- @field imageColor ColorValue 读写、Tweenable；图片颜色
--- @field imageType ImageType 读写；图片显示类型
--- @field enableMask boolean 读写；是否启用遮罩
--- @field enableSoftEdge boolean 读写；是否启用边缘羽化
--- @field softEdgeMode ImageMaskSoftEdgeMode 读写；边缘羽化模式
--- @field softEdgeWidthX number 读写、Tweenable；水平羽化宽度
--- @field softEdgeWidthY number 读写、Tweenable；垂直羽化宽度
--- @field horizontalSoftRange number 读写、Tweenable；水平羽化范围
--- @field verticalSoftRange number 读写、Tweenable；垂直羽化范围
--- @field reverseMaskArea boolean 读写；是否反转遮罩区域
--- @field fillType ImageFillType 读写；填充类型
--- @field fillHorizontalType ImageFillHorizontalType 读写；水平填充方向
--- @field fillVerticalType ImageFillVerticalType 读写；垂直填充方向
--- @field fillRadial90Type ImageFillRadial90Type 读写；90 度径向填充方向
--- @field fillRadialType ImageFillRadialType 读写；180/360 度径向填充方向
--- @field fillAmount number 读写、Tweenable；填充进度
ClientUIImageControl = {}

-- 方法

--- 设置图片来源与 ID
--- @param imageSource ImageSource
--- @param imageId integer
function ClientUIImageControl:SetImage(imageSource, imageId) end

--- 设置水平与垂直边缘羽化宽度
--- @param widthX number
--- @param widthY number
function ClientUIImageControl:SetSoftEdgeWidth(widthX, widthY) end

--- 关闭填充裁切
function ClientUIImageControl:SetFillUnused() end

--- 设置水平填充
--- @param fillHorizontalType ImageFillHorizontalType
--- @param fillAmount number
function ClientUIImageControl:SetFillHorizontal(fillHorizontalType, fillAmount) end

--- 设置垂直填充
--- @param fillVerticalType ImageFillVerticalType
--- @param fillAmount number
function ClientUIImageControl:SetFillVertical(fillVerticalType, fillAmount) end

--- 设置 90° 径向填充
--- @param fillRadial90Type ImageFillRadial90Type
--- @param fillAmount number
function ClientUIImageControl:SetFillRadial90(fillRadial90Type, fillAmount) end

--- 设置 180° 径向填充
--- @param fillRadialType ImageFillRadialType
--- @param fillAmount number
function ClientUIImageControl:SetFillRadial180(fillRadialType, fillAmount) end

--- 设置 360° 径向填充
--- @param fillRadialType ImageFillRadialType
--- @param fillAmount number
function ClientUIImageControl:SetFillRadial360(fillRadialType, fillAmount) end

-- ============================================================================
-- ClientUITextBoxControl 类型
-- ============================================================================

--- @class ClientUITextBoxControl : ClientUIBaseControl
--- @field text string 显示文本
--- @field fontSize integer Tweenable；字号
--- @field fontColor ColorValue Tweenable；文字颜色
--- @field bgColor ColorValue Tweenable；背景颜色
--- @field enableOutline boolean 是否启用描边
--- @field outlineColor ColorValue Tweenable；描边颜色
--- @field horizontalAlignment TextHorizontalAlignment 水平对齐方式
--- @field verticalAlignment TextVerticalAlignment 垂直对齐方式
--- @field adaptiveFontSize boolean 是否启用字号自适应
--- @field minimumFontSize integer 字号自适应时的最小字号
ClientUITextBoxControl = {}

-- ============================================================================
-- ClientUITextWindowControl 类型
-- ============================================================================

--- @class ClientUITextWindowControl : ClientUIBaseControl
--- @field interactable boolean 是否可交互；false 时手柄无响应
--- @field showScrollBar boolean 是否显示滚动条
--- @field text string 显示文本
--- @field fontSize integer Tweenable；字号
--- @field fontColor ColorValue Tweenable；文字颜色
--- @field bgColor ColorValue Tweenable；背景颜色
--- @field enableOutline boolean 是否启用描边
--- @field outlineColor ColorValue Tweenable；描边颜色
--- @field horizontalAlignment TextHorizontalAlignment 水平对齐方式
--- @field verticalAlignment TextVerticalAlignment 垂直对齐方式
--- @field adaptiveFontSize boolean 是否启用字号自适应
--- @field minimumFontSize integer 字号自适应时的最小字号
ClientUITextWindowControl = {}

-- ============================================================================
-- ClientUIPresetButtonControl 类型
-- ============================================================================

--- @class ClientUIPresetButtonControl : ClientUIBaseControl
--- @field interactable boolean 是否可交互
--- @field clickAudioId integer 点击音效 ID
--- @field raycastTarget boolean 是否可被光标射线检测
ClientUIPresetButtonControl = {}

--- 注册光标事件监听
--- @param eventType CursorEventType
--- @param callback fun(data: CursorEventData)
function ClientUIPresetButtonControl:AddCursorEventListener(eventType, callback) end

--- 移除指定事件和回调
--- @param eventType CursorEventType
--- @param callback fun(data: CursorEventData)
function ClientUIPresetButtonControl:RemoveCursorEventListener(eventType, callback) end

--- 移除指定光标事件的全部监听
--- @param eventType CursorEventType
function ClientUIPresetButtonControl:RemoveCursorEventListeners(eventType) end

--- 移除全部光标事件监听
function ClientUIPresetButtonControl:RemoveAllCursorEventListeners() end

--- 按顺序模拟 CursorDown -> CursorUp -> CursorClick
function ClientUIPresetButtonControl:SimulateCursorClick() end

-- ============================================================================
-- ClientUICursorEventAreaControl 类型
-- ============================================================================

--- @class ClientUICursorEventAreaControl : ClientUIBaseControl
--- @field raycastTarget boolean 是否可被光标射线检测
ClientUICursorEventAreaControl = {}

-- 方法

--- 注册光标事件监听
--- @param eventType CursorEventType
--- @param callback fun(data: CursorEventData)
function ClientUICursorEventAreaControl:AddCursorEventListener(eventType, callback) end

--- 移除指定事件和回调；callback 必须与注册时使用的引用相同
--- @param eventType CursorEventType
--- @param callback fun(data: CursorEventData)
function ClientUICursorEventAreaControl:RemoveCursorEventListener(eventType, callback) end

--- 移除指定光标事件的全部监听
--- @param eventType CursorEventType
function ClientUICursorEventAreaControl:RemoveCursorEventListeners(eventType) end

--- 移除全部光标事件监听
function ClientUICursorEventAreaControl:RemoveAllCursorEventListeners() end

--- 按顺序模拟 CursorDown -> CursorClick
function ClientUICursorEventAreaControl:SimulateCursorClick() end

-- ============================================================================
-- CursorEventData 类型
-- ============================================================================

--- @class CursorEventData
--- @field dragging boolean 只读；当前事件是否处于拖动状态
--- @field touchId integer 只读；触点 ID
CursorEventData = {}

-- 方法

--- 获取当前 UI 坐标
--- @return number, number
function CursorEventData:GetUIPos() end

--- 获取按下时的 UI 坐标
--- @return number, number
function CursorEventData:GetPressUIPos() end

--- 获取本次事件的位移增量
--- @return number, number
function CursorEventData:GetUIPosDelta() end

-- ============================================================================
-- ClientUIGridScrollerControl 类型
-- ============================================================================

--- @class ClientUIGridScrollerControl : ClientUIBaseControl
--- @field itemCount integer 只读；条目数量
--- @field itemPrefabIndex integer 读写；条目元件索引
--- @field raycastTarget boolean 读写；是否可被光标射线检测
--- @field showScrollBar boolean 读写；是否显示滚动条
--- @field interactable boolean 读写；是否可交互
--- @field scrollDirection ScrollDirection 只读；滚动方向
--- @field layoutConstraint ScrollLayoutConstraint 只读；布局约束
--- @field layoutConstraintFixedCount number 只读；固定行数或列数
--- @field scrollProgress number 读写、Tweenable；滚动进度
ClientUIGridScrollerControl = {}

-- 方法

--- 刷新条目并逐项回调；条目控件会复用，index 以运行时传入值为准
--- @param itemCount integer
--- @param refreshCallback fun(control: ClientUIBaseControl, index: integer)
function ClientUIGridScrollerControl:RefreshItems(itemCount, refreshCallback) end

--- 获取条目控件的序号
--- @param control ClientUIBaseControl
--- @return integer
function ClientUIGridScrollerControl:GetItemIndex(control) end

--- 获取条目宽度与高度
--- @return number, number
function ClientUIGridScrollerControl:GetItemSize() end

--- 获取条目的水平与垂直间距
--- @return number, number
function ClientUIGridScrollerControl:GetItemSpacing() end

--- 获取内容区域的内边距；返回顺序为 top、bottom、left、right
--- @return number, number, number, number -- top, bottom, left, right
function ClientUIGridScrollerControl:GetPadding() end

--- 滚动到指定序号
--- @param index integer
--- @param scrollAlignType ScrollAlignType
function ClientUIGridScrollerControl:ScrollToItemAt(index, scrollAlignType) end

--- 获取滚动内容在滚动方向上的长度
--- @return number
function ClientUIGridScrollerControl:GetContentLength() end

-- ============================================================================
-- ClientUIKeyHintControl 类型
-- ============================================================================

--- @class ClientUIKeyHintControl : ClientUIBaseControl
--- @field keyboardKeyCode KeyboardKeyCode 键鼠按键枚举值
--- @field controllerKeyCode ControllerKeyCode 手柄按键枚举值
ClientUIKeyHintControl = {}

-- ============================================================================
-- ClientUIAnimationControl 类型
-- ============================================================================

--- @class ClientUIAnimationControl : ClientUIBaseControl
--- @field animationId integer 动效 ID
--- @field playSoundEffect boolean 是否播放动效音效
--- @field layer UIAnimationLayer 动效层级
ClientUIAnimationControl = {}

-- 方法

--- 播放界面动效
function ClientUIAnimationControl:PlayAnimation() end

--- 停止界面动效
function ClientUIAnimationControl:StopAnimation() end

-- ============================================================================
-- ClientUIFullscreenAnimationControl 类型
-- ============================================================================

--- @class ClientUIFullscreenAnimationControl : ClientUIBaseControl
--- @field animationId integer 全屏动效 ID
--- @field playSoundEffect boolean 是否播放动效音效
ClientUIFullscreenAnimationControl = {}

-- ============================================================================
-- ClientUIContainerControl 类型
-- ============================================================================

--- @class ClientUIContainerControl : ClientUIBaseControl
--- @field isolateNavigation boolean 是否隔离手柄导航
--- @field disableKeyEventPassthrough boolean 是否屏蔽按键事件穿透
--- @field disableCursorEventPassthrough boolean 是否屏蔽区域内点击事件穿透
--- @field showCursor boolean 是否显示常驻光标
ClientUIContainerControl = {}

-- ============================================================================
-- ClientUIReferenceControl 类型
-- ============================================================================

--- @class ClientUIReferenceControl : ClientUIBaseControl
--- @field referencedPrefabIndex integer 只读；被引用的元件索引
ClientUIReferenceControl = {}

-- ============================================================================
-- EnumItem 类型
-- ============================================================================

--- @class EnumItem
--- @field Name string 枚举值名称
--- @field FullName string 枚举值完整名称
--- @field EnumType string 枚举类型名称
EnumItem = {}

-- ============================================================================
-- 生命周期回调函数（由运行时按名称调用）
-- ============================================================================

--- 脚本初始化时调用
function OnInit() end

--- 脚本启动时调用
function OnStart() end

--- 脚本启用时调用
function OnEnable() end

--- 脚本停用时调用
function OnDisable() end

--- 脚本逐帧更新时调用
--- @param dt number
function OnUpdate(dt) end

--- 关卡逐帧更新时调用
--- @param dt number
function OnLevelUpdate(dt) end

--- 脚本销毁时调用
function OnDestroy() end

return {
    Enum = Enum,
    typeof = typeof,
    print = print,
    printerr = printerr,
    debug = debug,
    game = game,
    math = math,
    script = script,
    Color = Color,
    Tween = Tween,
    TweenSequence = TweenSequence,
    ServerSignal = ServerSignal,
    ClientUIBaseControl = ClientUIBaseControl,
    ClientUIImageControl = ClientUIImageControl,
    ClientUITextBoxControl = ClientUITextBoxControl,
    ClientUITextWindowControl = ClientUITextWindowControl,
    ClientUIPresetButtonControl = ClientUIPresetButtonControl,
    ClientUICursorEventAreaControl = ClientUICursorEventAreaControl,
    ClientUIGridScrollerControl = ClientUIGridScrollerControl,
    ClientUIKeyHintControl = ClientUIKeyHintControl,
    ClientUIAnimationControl = ClientUIAnimationControl,
    ClientUIFullscreenAnimationControl = ClientUIFullscreenAnimationControl,
    ClientUIContainerControl = ClientUIContainerControl,
    ClientUIReferenceControl = ClientUIReferenceControl,
    CursorEventData = CursorEventData,
    EnumItem = EnumItem
}