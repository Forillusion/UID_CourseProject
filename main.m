function fig = main()
%MAIN  智能导航 UI 主入口
%  运行：直接在命令行输入 main 即可启动。
%  返回 figure 句柄（可选，便于测试）。
%  说明：本程序为 ISE 333 课程项目，纯手写实现（禁止高级内置函数）。
%        启动后所有操作均通过 UI 完成，无需命令行干预。

    %% ---------- 1. 创建主窗口 ----------
    fig = uifigure('Name', '智能导航 UI', ...
                   'Position', [100 100 1200 760], ...
                   'AutoResizeChildren','off', ...
                   'WindowButtonDownFcn', @onMouseDown, ...
                   'WindowButtonUpFcn',   @onMouseUp, ...
                   'SizeChangedFcn', @onResize);

    %% ---------- 2. 整体布局：左面板(320px) + 右画布（用 Position 定位） ----------
    panelWidth = 320;
    % 左侧控制面板
    panel = uipanel(fig, 'Title','', 'Units','pixels', ...
                    'Position', [0 0 panelWidth 760], ...
                    'BorderType','none', 'Tag','ctrlPanel');
    pnlChild = uigridlayout(panel, [1 1]);   % panel 内嵌 grid，便于后续排列控件

    % 右侧画布
    ax = uiaxes(fig, 'Units','pixels', ...
                'Position', [panelWidth 0 1200-panelWidth 760]);
    ax.Tag = 'mapAxes';
    set(ax, 'XLimMode','manual', 'YLimMode','manual', ...
            'XTick',[], 'YTick',[], 'Box','off', ...
            'XColor','none','YColor','none');
    ax.Toolbar.Visible = 'off';   % 关闭自带工具栏，避免误用缩放等

    %% ---------- 3. 初始化全局状态 S ----------
    S = struct();
    S.fig       = fig;
    S.ax        = ax;
    S.panel     = panel;     % uipanel（用于 onResize 调整 Position）
    S.pnlGrid   = pnlChild;  % gridlayout（用于往里放控件）
    S.mapOrigin = [];        % 原始地图矩阵（只读）
    S.mapDisplay= [];        % 当前显示用副本
    S.scale     = 1.7;       % 1 像素 = 1.7 米
    S.mapW      = 1404;      % 图像宽度（列数）—— 横向地图
    S.mapH      = 803;       % 图像高度（行数）
    S.mode      = 'idle';    % 交互模式状态机

    % —— OR1 道路骨架相关（后续步骤填充） ——
    S.sk.nodes  = zeros(0,2);  % [N x 2]，每行 [col, row]
    S.sk.edges  = zeros(0,2,'int32'); % [M x 2]，每行 [nodeIdx_i, nodeIdx_j] (1-based)
    S.roadMask  = [];          % [mapH x mapW logical]
    S.roadHalfWidth = 2;       % 道路半宽（像素），由滑块调整

    % —— 车辆相关（后续步骤） ——
    S.vehicles  = struct('id',{},'cx',{},'cy',{},'angle',{},'dispScale',{});
    S.nextIVid  = 1;

    % —— 测量暂存 ——
    S.measurePts = zeros(0,2);   % [K x 2]
    S.sketchChain = [];          % 当前折线正在输入的节点序号列表

    setappdata(fig, 'S', S);

    %% ---------- 4. 构建左侧控制面板 ----------
    h = buildPanel(pnlChild, fig);   % 在 gridlayout 里放控件，返回句柄
    S.handles = h;
    setS(fig, S);

    %% ---------- 5. 自动加载地图（路径相对于 main.m 所在文件夹） ----------
    mfileDir = fileparts(mfilename('fullpath'));
    if isempty(mfileDir), mfileDir = '.'; end
    mapPath = fullfile(mfileDir, 'MapForUI.jpg');
    if isfile(mapPath)
        S = getS(fig);
        S.mapOrigin  = imread(mapPath);
        S.mapDisplay = S.mapOrigin;
        [S.mapH, S.mapW, ~] = size(S.mapOrigin);
        setS(fig, S);
    end
    refreshView(fig);
    setStatus(fig, '就绪：已加载地图。点击地图任意点可查看世界坐标。');
end % main() 返回 fig


%% ====================================================================
%   左侧控制面板构建
%   返回 handles 结构体，包含所有需后续访问的控件句柄
%% ====================================================================
function h = buildPanel(pnl, fig)
    rows = 22;
    pnl.RowHeight = repmat({'fit'}, rows, 1);
    pnl.ColumnWidth = {'1x'};
    h = struct();
    r = 0;

    % 辅助函数：创建控件并放置到指定行
    function c = addC(type, rowIdx, varargin)
        c = feval(['ui' type], pnl, varargin{:});
        c.Layout.Row = rowIdx; c.Layout.Column = 1;
    end

    % ----- 标题 -----
    r = r + 1;
    addC('label', r, 'Text','智能导航 UI', 'FontSize',16, 'FontWeight','bold', ...
            'HorizontalAlignment','center');
    r = r + 1;
    addC('label', r, 'Text','1像素 = 1.7 米   地图: 1404×803', 'FontSize',9);

    % ----- 地图分组 -----
    r = r + 1;
    addC('label', r, 'Text','──── 地图 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    addC('label', r, 'Text','旋转角度 (度):');
    r = r + 1;
    h.rotEdit = addC('editfield', r, 'numeric', 'Value',0, 'Limits',[-360 360], ...
                     'ValueChangedFcn', @(s,e) onRotChanged(fig,s));

    % ----- 骨架分组（步骤 B 填充） -----
    r = r + 1;
    addC('label', r, 'Text','──── 道路骨架 (OR1) ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    addC('label', r, 'Text','(步骤B 实现)', 'FontSize',8, 'FontAngle','italic');

    % ----- 智能车分组（占位） -----
    r = r + 1;
    addC('label', r, 'Text','──── 智能车 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    addC('label', r, 'Text','(步骤D 实现)', 'FontSize',8, 'FontAngle','italic');

    % ----- 测量分组（占位） -----
    r = r + 1;
    addC('label', r, 'Text','──── 测量 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    addC('label', r, 'Text','(步骤F 实现)', 'FontSize',8, 'FontAngle','italic');

    % ----- 坐标显示 -----
    r = r + 1;
    addC('label', r, 'Text','──── 坐标 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    h.coordX = addC('label', r, 'Text','X: --- m');
    r = r + 1;
    h.coordY = addC('label', r, 'Text','Y: --- m');

    % ----- 状态栏 -----
    r = r + 1;
    h.statusBar = addC('label', r, 'Text','当前: ---', 'FontAngle','italic');
end


%% ====================================================================
%   鼠标交互（本步骤：仅显示坐标）
%% ====================================================================
function onMouseDown(fig, ~)
    S = getS(fig);
    if isempty(S.mapOrigin), return; end
    pt = getPointerOnAxes(fig, S.ax);
    if isempty(pt), return; end
    col = pt(1); row = pt(2);
    [wx, wy] = px2world(fig, col, row);
    % 更新面板坐标显示
    S = getS(fig);
    if isfield(S,'handles')
        set(S.handles.coordX, 'String', sprintf('X: %.2f m', wx));
        set(S.handles.coordY, 'String', sprintf('Y: %.2f m', wy));
    end
end

function onMouseUp(fig, ~)
    % 预留：拖拽相关
end

function onResize(fig, ~)
%ONRESIZE  窗口大小改变时，重排左面板和右画布
    S = getS(fig);
    if ~isfield(S,'panel') || ~isfield(S,'ax'), return; end
    pos = get(fig, 'Position');
    panelWidth = 320;
    set(S.panel, 'Position', [0 0 panelWidth pos(4)]);
    set(S.ax,    'Position', [panelWidth 0 pos(3)-panelWidth pos(4)]);
end


%% ====================================================================
%   旋转地图（占位回调，步骤 E 实现）
%% ====================================================================
function onRotChanged(fig, src)
    % 步骤 E 实现
    deg = src.Value;
    if deg == 0, return; end
    setStatus(fig, sprintf('地图旋转功能将在步骤E实现 (当前 %g°)', deg));
end


%% ====================================================================
%   核心工具函数
%% ====================================================================
function out = getS(fig)
%GETS  读取全局状态
    out = getappdata(fig, 'S');
end

function setS(fig, S)
%SETS  写入全局状态
    setappdata(fig, 'S', S);
end

function setStatus(fig, msg)
%SETSTATUS  更新左下角状态栏
    try
        S = getS(fig);
        if isfield(S,'handles') && isfield(S.handles,'statusBar')
            sb = S.handles.statusBar;
            if isvalid(sb)
                sb.Text = ['当前: ' msg];
            end
        end
    catch
        % 静默忽略（batch 模式下 UI 控件可能受限）
    end
end

function refreshView(fig)
%REFRESHVIEW  把当前 mapDisplay 显示到 axes
    S = getS(fig);
    if isempty(S.mapDisplay), return; end
    imshow(S.mapDisplay, 'Parent', S.ax);
    axis(S.ax, 'image');
    % 固定坐标，方便后续 get(gca,'CurrentPoint') 取像素
    set(S.ax, 'XLim',[0.5 S.mapW+0.5], 'YLim',[0.5 S.mapH+0.5], ...
              'YDir','normal');
    % 注：YDir='normal' 让 row 向上，但 imshow 默认是 YDir='reverse'
    % 我们统一用 reverse，便于和图像矩阵对应
    set(S.ax, 'YDir','reverse');
end

function pt = getPointerOnAxes(fig, ax)
%GETPOINTERONAXES  返回鼠标在 axes 上的 [col, row]（连续值）
    pt = [];
    if ~isgraphics(ax), return; end
    cp = get(ax, 'CurrentPoint');
    if isempty(cp), return; end
    col = cp(1,1); row = cp(1,2);
    % 必须在图像范围内
    S = getS(fig);
    if col < 1 || col > S.mapW || row < 1 || row > S.mapH
        return;
    end
    pt = [col row];
end

function [wx, wy] = px2world(fig, col, row)
%PX2WORLD  像素坐标 -> 世界坐标（米）
%  现实原点 = 图像左下角；X 向右；Y 向上
    S = getS(fig);
    wx = col * S.scale;
    wy = (S.mapH - row) * S.scale;
end

function [col, row] = world2px(fig, wx, wy)
%WORLD2PX  世界坐标(米) -> 像素坐标
    S = getS(fig);
    col = wx / S.scale;
    row = S.mapH - wy / S.scale;
end
