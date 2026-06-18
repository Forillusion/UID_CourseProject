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
                   'WindowButtonMotionFcn', @onMouseMove, ...
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
    S.basicRoadMask = [];    % Basic 阶段手工道路 mask（非 OR1）
    S.scale     = 1.7;       % 1 像素 = 1.7 米
    S.mapW      = 1404;      % 图像宽度（列数）—— 横向地图
    S.mapH      = 803;       % 图像高度（行数）
    S.mode      = 'idle';    % 交互模式状态机
    S.sketchState = 'idle';  % 骨架工作流: idle/sketching/erasing/finalized
    S.rotDeg    = 0;         % 当前地图旋转角度
    S.rotSize   = [];        % 旋转后画布尺寸 [newH newW]（空=未旋转）
    S.rotCX     = [];        % 普通旋转模式的旋转中心 x（列）
    S.rotCY     = [];        % 普通旋转模式的旋转中心 y（行）
    S.dispH     = S.mapH;    % 当前显示图高度（行）
    S.dispW     = S.mapW;    % 当前显示图宽度（列）
    S.viewZoom  = 1;         % 显示缩放倍率（只改 axes 视窗，不改图像矩阵）
    S.viewCenter = [];       % 当前视窗中心 [col row]，空=图像中心
    S.isPanning = false;
    S.panStartPoint = [];
    S.panStartXLim = [];
    S.panStartYLim = [];

    % —— OR1 道路骨架相关（后续步骤填充） ——
    S.sk.nodes  = zeros(0,2);  % [N x 2]，每行 [col, row]
    S.sk.edges  = zeros(0,2,'int32'); % [M x 2]，每行 [nodeIdx_i, nodeIdx_j] (1-based)
    S.roadMask  = [];          % [mapH x mapW logical]
    S.roadHalfWidth = 2;       % 道路半宽（像素），由滑块调整

    % —— 车辆相关（后续步骤） ——
    S.vehicles  = struct('id',{},'cx',{},'cy',{},'angle',{},'dispScale',{});
    S.nextIVid  = 1;

    % —— OR3 车头朝上模式 ——
    S.headUpMode  = false;   % 是否启用"车头始终朝上"显示模式
    S.headUpAngle = 0;       % 车头朝上模式使用的车辆角度（度）
    S.headUpCX    = [];      % 车头朝上模式旋转中心 x（列）
    S.headUpCY    = [];      % 车头朝上模式旋转中心 y（行）

    % —— 测量暂存 ——
    S.measurePts = zeros(0,2);   % [K x 2]
    S.sketchChain = [];          % 当前折线正在输入的节点序号列表

    % —— 函数句柄（供 or1_skeleton.m 跨文件调用） ——
    S.fn = struct();
    S.fn.refresh = @refreshDisplay;
    S.fn.setStatus = @setStatus;
    S.fn.updateDropdown = @updateIVDropdown;

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
        basicMaskPath = fullfile(mfileDir, 'RoadMask.jpg');
        if isfile(basicMaskPath)
            maskImage = imread(basicMaskPath);
            if size(maskImage, 1) == S.mapH && size(maskImage, 2) == S.mapW
                S.basicRoadMask = maskImage;
            end
        end
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
    rows = 33;
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
    h.rotLabel = addC('label', r, 'Text','旋转角度 (度): 0');
    r = r + 1;
    h.rotSlider = addC('slider', r, 'Value',0, 'Limits',[-180 180], ...
                       'MajorTicks',[-180 -90 0 90 180], ...
                       'ValueChangedFcn', @(s,e) onRotChanged(fig,s));
    r = r + 1;
    h.zoomLabel = addC('label', r, 'Text','显示缩放: 1.0x');
    r = r + 1;
    h.zoomSlider = addC('slider', r, 'Value',1, 'Limits',[1 4], ...
                        'MajorTicks',[1 2 3 4], ...
                        'ValueChangedFcn', @(s,e) onZoomChanged(fig,s));
    r = r + 1;
    h.btnResetView = addC('button', r, 'Text','重置视图', ...
                          'ButtonPushedFcn', @(s,e) onResetView(fig));

    % ----- 可选功能入口 -----
    r = r + 1;
    addC('label', r, 'Text','──── 可选功能 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    h.btnOR1 = addC('button', r, 'Text','OR1 道路骨架', ...
                    'ButtonPushedFcn', @(s,e) or1_skeleton('open', fig));
    r = r + 1;
    h.btnOR2 = addC('button', r, 'Text','OR2 预留', 'Enable','off');
    r = r + 1;
    h.btnOR3 = addC('button', r, 'Text','OR3 车辆朝向', ...
                    'ButtonPushedFcn', @(s,e) onBtnOR3(fig));
    r = r + 1;
    h.btnOR4 = addC('button', r, 'Text','OR4 虚拟街景', ...
                    'ButtonPushedFcn', @(s,e) or4_street_view('open', fig));
    r = r + 1;
    h.btnOR5 = addC('button', r, 'Text','OR5 路径规划', ...
                    'ButtonPushedFcn', @(s,e) or5_path_planning('open', fig));

    % ----- 智能车分组 -----
    r = r + 1;
    addC('label', r, 'Text','──── 智能车 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    h.btnLoadIV = addC('button', r, 'Text','加载车辆', ...
                       'ButtonPushedFcn', @(s,e) onBtnLoadIV(fig));
    r = r + 1;
    h.btnRemoveIV = addC('button', r, 'Text','移除车辆', ...
                         'ButtonPushedFcn', @(s,e) onBtnRemoveIV(fig));
    r = r + 1;
    addC('label', r, 'Text','选择车辆:', 'FontSize',9);
    r = r + 1;
    h.ivDropdown = addC('dropdown', r, 'Items', {'(无车辆)'}, ...
                        'Value', '(无车辆)', ...
                        'ValueChangedFcn', @(s,e) onIVDropdownChanged(fig));
    r = r + 1;
    addC('label', r, 'Text','朝向调整(度):', 'FontSize',9);
    r = r + 1;
    h.angleSlider = addC('slider', r, 'Value',0, 'Limits',[0 360], ...
                         'MajorTicks',[0 90 180 270 360], ...
                         'ValueChangedFcn', @(s,e) onAngleChanged(fig,s));
    r = r + 1;
    h.angleValue = addC('label', r, 'Text','当前: 0°', 'FontSize',9);
    % —— OR3 复选框 ——
    r = r + 1;
    h.chkAutoAlign = addC('checkbox', r, 'Text','自动对齐道路方向 (OR3)', ...
                          'Value', true);
    r = r + 1;
    h.chkHeadUp = addC('checkbox', r, 'Text','车头始终朝上 (OR3)', ...
                       'Value', false, ...
                       'ValueChangedFcn', @(s,e) onHeadUpToggled(fig, s));
    r = r + 1;
    h.btnReportIV = addC('button', r, 'Text','报告位置', ...
                         'ButtonPushedFcn', @(s,e) onBtnReportIV(fig));
    r = r + 1;
    addC('label', r, 'Text','提示: IV 只能加载在道路上', 'FontSize',8, 'FontAngle','italic');

    % ----- 测量分组 -----
    r = r + 1;
    addC('label', r, 'Text','──── 测量 ────', 'FontSize',11, 'FontWeight','bold');
    r = r + 1;
    h.btnMeasure2 = addC('button', r, 'Text','两点测距', ...
                         'ButtonPushedFcn', @(s,e) onBtnMeasure2(fig));
    r = r + 1;
    h.btnTrack = addC('button', r, 'Text','轨迹测量', ...
                      'ButtonPushedFcn', @(s,e) onBtnTrack(fig));
    r = r + 1;
    h.btnClearMeasure = addC('button', r, 'Text','清除测量标记', ...
                             'ButtonPushedFcn', @(s,e) onBtnClearMeasure(fig));
    r = r + 1;
    h.measureLabel = addC('label', r, 'Text','距离: ---', 'FontSize',9, 'FontWeight','bold');

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
%ONMOUSEDOWN  主鼠标按下回调，按 mode + 按键类型分发
    S = getS(fig);
    if isempty(S.mapOrigin), return; end
    if strcmp(S.mode, 'idle') && isPointerInDisplay(fig, S.ax)
        cp = get(S.ax, 'CurrentPoint');
        S.isPanning = true;
        S.panStartPoint = cp(1,1:2);
        S.panStartXLim = S.ax.XLim;
        S.panStartYLim = S.ax.YLim;
        setS(fig, S);
    end
    pt = getPointerOnAxes(fig, S.ax);
    if isempty(pt), return; end
    col = pt(1); row = pt(2);
    selType = get(fig, 'SelectionType');   % 'normal'=左键 'alt'=右键

    % 始终更新坐标显示
    [wx, wy] = px2world(fig, col, row);
    if isfield(S,'handles')
        try
            S.handles.coordX.Text = sprintf('X: %.2f m', wx);
            S.handles.coordY.Text = sprintf('Y: %.2f m', wy);
        catch; end
    end

    % 按模式分发
    switch S.mode
        case {'sketch', 'erase'}
            or1_skeleton('click', fig, col, row, selType);
        case 'loadIV'
            handleLoadIVClick(fig, col, row);
        case 'or4'
            or4_street_view('click', fig, col, row, selType);
        case {'or5_start','or5_end'}
            or5_path_planning('click', fig, col, row, selType);
        case 'measure2'
            handleMeasure2Click(fig, col, row);
        case 'track'
            handleTrackClick(fig, col, row);
        otherwise
            % idle：仅显示坐标，已在上面处理
    end
end

function onMouseMove(fig, ~)
    S = getS(fig);
    if ~isfield(S,'isPanning') || ~S.isPanning || isempty(S.panStartPoint)
        return;
    end
    cp = get(S.ax, 'CurrentPoint');
    delta = cp(1,1:2) - S.panStartPoint;
    startCenter = [mean(S.panStartXLim), mean(S.panStartYLim)];
    S.viewCenter = startCenter - delta;
    setS(fig, S);
    applyViewLimits(fig);
end

function onMouseUp(fig, ~)
    S = getS(fig);
    if isfield(S,'isPanning')
        S.isPanning = false;
        setS(fig, S);
    end
end

function map = overlaySkeleton(map, nodes, edges, mapW, mapH)
%OVERLAYSKELETON  在地图矩阵上叠加骨架（粗实红线 + 黄色节点），纯函数无副作用
    [H, W, ~] = size(map);
    lineColor = uint8([255 0 0]);   % 红色实线
    nodeColor = uint8([255 255 0]); % 黄色节点
    lineR = 1;   % 线半宽=1 -> 3px 粗实线（避免对角线断裂成虚线）
    nodeR = 2;
    for i = 1:size(edges, 1)
        ni = edges(i,1); nj = edges(i,2);
        A = nodes(ni,:); B = nodes(nj,:);
        pxs = bresenham(A(1), A(2), B(1), B(2));
        for k = 1:size(pxs,1)
            map = stampSquare(map, pxs(k,1), pxs(k,2), lineR, lineColor, W, H);
        end
    end
    for i = 1:size(nodes, 1)
        map = stampSquare(map, nodes(i,1), nodes(i,2), nodeR, nodeColor, W, H);
    end
end

function map = stampSquare(map, cx, cy, radius, color, W, H)
%STAMPSQUARE  在 (cx,cy) 处盖一个 (2*radius+1) 的实心方块
    cc0 = round(cx); rr0 = round(cy);
    for dr = -radius:radius
        for dc = -radius:radius
            rr = rr0 + dr; cc = cc0 + dc;
            if cc>=1 && cc<=W && rr>=1 && rr<=H
                map(rr, cc, :) = color;
            end
        end
    end
end

%% ====================================================================
%   智能车 (IV) 相关
%% ====================================================================
function handleLoadIVClick(fig, col, row)
%HANDLELOADIVCLICK  loadIV 模式下点击地图加载车辆
    S = getS(fig);
    rc = round(row); cc = round(col);
    if rc < 1 || rc > S.mapH || cc < 1 || cc > S.mapW
        setStatus(fig, '点击点超出地图范围。');
        return;
    end

    isRoad = isRoadPointForUI(S.mapOrigin, S.basicRoadMask, S.roadMask, rc, cc);
    if ~isRoad
        setStatus(fig, sprintf('无效点 (%.0f,%.0f)：不在道路上！', col, row));
        uialert(S.fig, '该点不在道路上，无法加载车辆。', '加载失败');
        return;
    end
    % 有效：添加车辆
    angle = 0;
    if isfield(S.handles,'angleSlider') && isvalid(S.handles.angleSlider)
        angle = S.handles.angleSlider.Value;
    end
    % OR3 自动对齐：复选框启用时，覆盖用户手动角度
    if isfield(S.handles,'chkAutoAlign') && isvalid(S.handles.chkAutoAlign) ...
            && S.handles.chkAutoAlign.Value
        angle = or3_auto_align('findAngle', fig, col, row);
    end
    v.id = S.nextIVid;
    v.cx = col; v.cy = row;
    v.angle = angle;
    v.dispScale = 3;   % 显示放大倍数（真实尺寸太小）
    S.vehicles(end+1) = v;   %#ok<AGROW>
    S.nextIVid = S.nextIVid + 1;
    S.mode = 'idle';
    setS(fig, S);
    refreshDisplay(fig);
    updateIVDropdown(fig);
    [wx, wy] = px2world(fig, col, row);
    setStatus(fig, sprintf('车辆 #%d 已加载 @ (%.1f, %.1f)m，朝向 %.0f°', ...
              v.id, wx, wy, v.angle));
end

function map = buildBaseMap(fig)
    S = getS(fig); map = S.mapOrigin;
    if isempty(map), return; end
    switch S.sketchState
        case {'sketching','erasing'}
            if ~isempty(S.sk.edges)
                map = overlaySkeleton(map, S.sk.nodes, S.sk.edges, S.mapW, S.mapH);
            end
        case 'finalized'
            if ~isempty(S.roadMask), map = overlayBlueRoad(map, S.roadMask); end
    end
    for i = 1:numel(S.vehicles)
        map = drawIV(map, S.vehicles(i).cx, S.vehicles(i).cy, ...
            S.vehicles(i).angle, S.vehicles(i).dispScale, S.mapW, S.mapH, S.scale);
        map = drawIVIdLabel(map, S.vehicles(i).id, S.vehicles(i).cx, S.vehicles(i).cy, S.mapW, S.mapH);
    end
    % OR4：叠加相机标记（位置 + FOV 锥形）
    if isfield(S, 'or4') && ~isempty(S.or4) && isfield(S.or4, 'cam')
        map = or4_street_view('drawCam', fig, map);
    end
    % OR5：叠加路径/起终点
    if isfield(S, 'or5') && ~isempty(S.or5)
        map = or5_path_planning('overlay', fig, map);
    end
end

function map = overlayBlueRoad(map, roadMask)
    m = roadMask;
    R = double(map(:,:,1)); G = double(map(:,:,2)); B = double(map(:,:,3));
    R(m) = R(m)*0.5+15; G(m) = G(m)*0.5+50; B(m) = B(m)*0.5+110;
    map = uint8(cat(3,R,G,B));
end

function isRoad = isBasicRoadPoint(mapImage, basicRoadMask, row, col)
%ISBASICROADPOINT  Basic road check without using OR1.
%  Use a hand-drawn RoadMask.jpg when available, then reject obvious
%  non-road colors such as green fields or blue water.
    [H, W, ~] = size(mapImage);
    radius = 3;
    roadLikeCount = 0;
    totalCount = 0;

    maskOk = ~isempty(basicRoadMask) && hasBasicMaskRoadNearby(basicRoadMask, row, col);

    for r = row-radius:row+radius
        for c = col-radius:col+radius
            if r >= 1 && r <= H && c >= 1 && c <= W
                totalCount = totalCount + 1;
                redValue = double(mapImage(r, c, 1));
                greenValue = double(mapImage(r, c, 2));
                blueValue = double(mapImage(r, c, 3));

                maxValue = max([redValue greenValue blueValue]);
                minValue = min([redValue greenValue blueValue]);
                averageValue = (redValue + greenValue + blueValue) / 3;

                greenDominance = greenValue - min(redValue, blueValue);
                blueDominance = blueValue - min(redValue, greenValue);

                isBright = averageValue > 135;
                isGrayLike = (maxValue - minValue) < 70;
                isNotGreenArea = greenDominance < 35;
                isNotWater = blueDominance < 45;

                if isBright && isGrayLike && isNotGreenArea && isNotWater
                    roadLikeCount = roadLikeCount + 1;
                end
            end
        end
    end

    colorOk = roadLikeCount >= totalCount * 0.35;
    isRoad = maskOk || colorOk;
end

function hasRoad = hasBasicMaskRoadNearby(maskImage, row, col)
%HASBASICMASKROADNEARBY  Allow small hand-drawing error in RoadMask.jpg.
    [H, W, ~] = size(maskImage);
    toleranceRadius = 14;
    hasRoad = false;

    for r = row-toleranceRadius:row+toleranceRadius
        for c = col-toleranceRadius:col+toleranceRadius
            if r >= 1 && r <= H && c >= 1 && c <= W
                if isMaskPixelWhite(maskImage, r, c)
                    hasRoad = true;
                    return;
                end
            end
        end
    end
end

function isWhite = isMaskPixelWhite(maskImage, row, col)
    if size(maskImage, 3) == 3
        redValue = double(maskImage(row, col, 1));
        greenValue = double(maskImage(row, col, 2));
        blueValue = double(maskImage(row, col, 3));
        maskValue = (redValue + greenValue + blueValue) / 3;
    else
        maskValue = double(maskImage(row, col));
    end
    isWhite = maskValue > 160;
end

function refreshDisplay(fig)
    S = getS(fig); if isempty(S.mapOrigin), return; end
    map = buildBaseMap(fig);
    if S.headUpMode
        % OR3 车头朝上模式：绕选定车辆中心旋转地图
        vAngle = S.headUpAngle;
        vcx    = S.mapW / 2;
        vcy    = S.mapH / 2;
        if ~isempty(S.vehicles) && isfield(S.handles,'ivDropdown') && isvalid(S.handles.ivDropdown)
            sel = S.handles.ivDropdown.Value;
            tok = regexp(sel, '#(\d+)', 'tokens', 'once');
            if ~isempty(tok)
                vid = str2double(tok{1});
                idx = find(arrayfun(@(v) v.id==vid, S.vehicles), 1);
                if ~isempty(idx)
                    vAngle = S.vehicles(idx).angle;
                    vcx    = S.vehicles(idx).cx;
                    vcy    = S.vehicles(idx).cy;
                    S.headUpAngle = vAngle;
                end
            end
        end
        S.mapDisplay = or3_auto_align('rotateAround', map, vcx, vcy, headUpRotation(vAngle));
        S.rotSize    = [size(S.mapDisplay,1), size(S.mapDisplay,2)];
        S.rotCX      = [];
        S.rotCY      = [];
        S.headUpCX   = vcx;
        S.headUpCY   = vcy;
    elseif S.rotDeg ~= 0
        if isempty(S.rotCX) || isempty(S.rotCY)
            S.rotCX = (S.mapW + 1) / 2;
            S.rotCY = (S.mapH + 1) / 2;
        end
        S.mapDisplay = rotateMapAroundPoint(map, S.rotCX, S.rotCY, S.rotDeg);
        S.rotSize    = [size(S.mapDisplay,1), size(S.mapDisplay,2)];
        S.viewCenter = mapOriginalPointToDisplay(S, S.rotCX, S.rotCY);
        S.headUpCX   = [];
        S.headUpCY   = [];
    else
        S.mapDisplay = map;
        S.rotSize    = [];
        S.rotCX      = [];
        S.rotCY      = [];
        S.headUpCX   = [];
        S.headUpCY   = [];
    end
    setS(fig, S); refreshView(fig);
end

function deg = headUpRotation(vehicleAngle)
%HEADUPROTATION  UI 中补偿到车头朝上。
    deg = 90 - vehicleAngle;
end

function mapOut = drawIV(mapIn, cx, cy, angleDeg, dispScale, mapW, mapH, scale)
%DRAWIV  手搓绘制单辆 IV（旋转矩形）到地图矩阵上
%  真实 IV: 8m x 3m -> 像素 8/1.7 x 3/1.7 ≈ 4.7 x 1.8 -> x dispScale
%  车身为绿色，车头前段为黄色（与车身同宽）
    L = (8 / scale) * dispScale;   % 长（像素）
    Wd = (3 / scale) * dispScale;  % 宽（像素）
    headLen = L * 0.25;            % 车头长度（占全长 1/4）
    bodyLen = L - headLen;         % 车身长度
    th = angleDeg * pi / 180;
    R = [cos(th) -sin(th); sin(th) cos(th)];

    % —— 1. 画车身（绿色）：从中心偏后 headLen/2 开始 ——
    bodyCorners = [-(bodyLen/2 + headLen/2) -Wd/2; ...
                    (headLen - (bodyLen/2 + headLen/2)) -Wd/2; ...
                    (headLen - (bodyLen/2 + headLen/2))  Wd/2; ...
                   -(bodyLen/2 + headLen/2)  Wd/2];
    % 简化：车身后端 x = -L/2，前端 x = -L/2 + bodyLen = headLen - L/2
    bodyCorners = [-L/2 -Wd/2; headLen-L/2 -Wd/2; headLen-L/2 Wd/2; -L/2 Wd/2];
    bodyPts = bodyCorners * R' + [cx, cy];
    mapOut = mapIn;
    bodyColor = uint8([0 200 0]);   % 绿色车身
    [cMin, cMax, rMin, rMax] = polyBBox(bodyPts, mapW, mapH);
    for r = rMin:rMax
        for c = cMin:cMax
            if pointInPolygon([c, r], bodyPts)
                mapOut(r, c, :) = bodyColor;
            end
        end
    end

    % —— 2. 画车头（黄色）：前端段，与车身同宽 ——
    headCorners = [headLen-L/2 -Wd/2; L/2 -Wd/2; L/2 Wd/2; headLen-L/2 Wd/2];
    headPts = headCorners * R' + [cx, cy];
    headColor = uint8([255 255 0]); % 黄色车头
    [cMin, cMax, rMin, rMax] = polyBBox(headPts, mapW, mapH);
    for r = rMin:rMax
        for c = cMin:cMax
            if pointInPolygon([c, r], headPts)
                mapOut(r, c, :) = headColor;
            end
        end
    end
end

function [cMin, cMax, rMin, rMax] = polyBBox(ptsPx, mapW, mapH)
%POLYBBOX  计算多边形的像素 bounding box（钳制到地图范围）
    cMin = max(1, floor(min(ptsPx(:,1))));
    cMax = min(mapW, ceil(max(ptsPx(:,1))));
    rMin = max(1, floor(min(ptsPx(:,2))));
    rMax = min(mapH, ceil(max(ptsPx(:,2))));
end

function inside = pointInPolygon(pt, poly)
%POINTINPOLYGON  射线法判断点是否在多边形内（手写）
    n = size(poly, 1);
    inside = false;
    j = n;
    for i = 1:n
        yi = poly(i,2); yj = poly(j,2);
        xi = poly(i,1); xj = poly(j,1);
        if ((yi > pt(2)) ~= (yj > pt(2)))
            xCross = xi + (pt(2)-yi)/(yj-yi) * (xj-xi);
            if pt(1) < xCross
                inside = ~inside;
            end
        end
        j = i;
    end
end

function mapOut = drawIVIdLabel(mapIn, id, cx, cy, mapW, mapH)
%DRAWIVIDLABEL  手写像素数字，在 IV 附近标注编号。
    textColor = uint8([255 0 0]);
    bgColor = uint8([255 255 255]);
    scale = 2;
    digitGap = 1;
    idText = num2str(id);
    digitW = 3 * scale;
    digitH = 5 * scale;
    labelW = length(idText) * digitW + (length(idText)-1) * digitGap + 4;
    labelH = digitH + 4;

    startCol = round(cx - labelW / 2);
    startRow = round(cy - 20 - labelH);
    if startRow < 1
        startRow = round(cy + 16);
    end
    startCol = max(1, min(mapW - labelW + 1, startCol));
    startRow = max(1, min(mapH - labelH + 1, startRow));

    mapOut = fillRectOnImage(mapIn, startRow, startCol, labelH, labelW, bgColor, mapW, mapH);

    digitCol = startCol + 2;
    digitRow = startRow + 2;
    for k = 1:length(idText)
        mapOut = drawDigitOnImage(mapOut, idText(k), digitRow, digitCol, scale, textColor, mapW, mapH);
        digitCol = digitCol + digitW + digitGap;
    end
end

function mapOut = fillRectOnImage(mapIn, row, col, rectH, rectW, color, mapW, mapH)
    mapOut = mapIn;
    r1 = max(1, row);
    r2 = min(mapH, row + rectH - 1);
    c1 = max(1, col);
    c2 = min(mapW, col + rectW - 1);
    for r = r1:r2
        for c = c1:c2
            mapOut(r, c, :) = color;
        end
    end
end

function mapOut = drawDigitOnImage(mapIn, digitChar, row, col, scale, color, mapW, mapH)
    pattern = digitPattern(digitChar);
    mapOut = mapIn;
    for pr = 1:5
        for pc = 1:3
            if pattern(pr, pc) == 1
                for sr = 0:scale-1
                    for sc = 0:scale-1
                        rr = row + (pr-1)*scale + sr;
                        cc = col + (pc-1)*scale + sc;
                        if rr >= 1 && rr <= mapH && cc >= 1 && cc <= mapW
                            mapOut(rr, cc, :) = color;
                        end
                    end
                end
            end
        end
    end
end

function p = digitPattern(digitChar)
    switch digitChar
        case '0'
            p = [1 1 1; 1 0 1; 1 0 1; 1 0 1; 1 1 1];
        case '1'
            p = [0 1 0; 1 1 0; 0 1 0; 0 1 0; 1 1 1];
        case '2'
            p = [1 1 1; 0 0 1; 1 1 1; 1 0 0; 1 1 1];
        case '3'
            p = [1 1 1; 0 0 1; 0 1 1; 0 0 1; 1 1 1];
        case '4'
            p = [1 0 1; 1 0 1; 1 1 1; 0 0 1; 0 0 1];
        case '5'
            p = [1 1 1; 1 0 0; 1 1 1; 0 0 1; 1 1 1];
        case '6'
            p = [1 1 1; 1 0 0; 1 1 1; 1 0 1; 1 1 1];
        case '7'
            p = [1 1 1; 0 0 1; 0 1 0; 0 1 0; 0 1 0];
        case '8'
            p = [1 1 1; 1 0 1; 1 1 1; 1 0 1; 1 1 1];
        case '9'
            p = [1 1 1; 1 0 1; 1 1 1; 0 0 1; 1 1 1];
        otherwise
            p = zeros(5, 3);
    end
end

function updateIVDropdown(fig)
%UPDATEIVDROPDOWN  更新车辆下拉列表
    S = getS(fig);
    items = {'(无车辆)'};
    if ~isempty(S.vehicles)
        items = arrayfun(@(v) sprintf('#%d (%.0f,%.0f)', v.id, v.cx, v.cy), ...
                         S.vehicles, 'UniformOutput', false);
    end
    dd = S.handles.ivDropdown;
    dd.Items = items;
    if ~isempty(S.vehicles)
        dd.Value = items{end};
    else
        dd.Value = '(无车辆)';
    end
end

function onBtnLoadIV(fig)
    S = getS(fig);
    if strcmp(S.mode, 'loadIV')
        % 已在加载模式，再次点击取消
        S.mode = 'idle';
        setS(fig, S);
        setStatus(fig, '加载车辆模式已取消。');
        return;
    end
    S.mode = 'loadIV';
    setS(fig, S);
    setStatus(fig, '加载车辆模式：点击地图上的道路位置放置车辆。（再次点击"加载车辆"可取消）');
end

function onBtnRemoveIV(fig)
    S = getS(fig);
    if isempty(S.vehicles)
        setStatus(fig, '无车辆可移除。');
        return;
    end

    if isfield(S, 'removeFig') && ~isempty(S.removeFig) && isvalid(S.removeFig)
        figure(S.removeFig);
        return;
    end

    removeFig = uifigure('Name', '选择要移除的 IV', ...
                         'Position', [220 220 320 300], ...
                         'Resize', 'off');
    gl = uigridlayout(removeFig, [4 2]);
    gl.RowHeight = {'fit', '1x', 'fit', 'fit'};
    gl.ColumnWidth = {'1x', '1x'};

    titleLabel = uilabel(gl, 'Text', '请选择要移除的 IV 编号：', ...
        'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    titleLabel.Layout.Row = 1;
    titleLabel.Layout.Column = [1 2];

    items = cell(1, numel(S.vehicles));
    for i = 1:numel(S.vehicles)
        [wx, wy] = px2world(fig, S.vehicles(i).cx, S.vehicles(i).cy);
        items{i} = sprintf('#%d  位置(%.1f, %.1f)m  朝向 %.0f°', ...
            S.vehicles(i).id, wx, wy, S.vehicles(i).angle);
    end
    listBox = uilistbox(gl, 'Items', items);
    listBox.Layout.Row = 2;
    listBox.Layout.Column = [1 2];

    confirmBtn = uibutton(gl, 'Text', '移除所选 IV', ...
        'ButtonPushedFcn', @(~,~) confirmRemoveIV(fig, removeFig, listBox));
    confirmBtn.Layout.Row = 3;
    confirmBtn.Layout.Column = 1;

    cancelBtn = uibutton(gl, 'Text', '取消', ...
        'ButtonPushedFcn', @(~,~) close(removeFig));
    cancelBtn.Layout.Row = 3;
    cancelBtn.Layout.Column = 2;

    hint = uilabel(gl, 'Text', '提示：只会移除列表中选中的一辆 IV。', ...
        'FontAngle', 'italic');
    hint.Layout.Row = 4;
    hint.Layout.Column = [1 2];

    S.removeFig = removeFig;
    setS(fig, S);
end

function confirmRemoveIV(fig, removeFig, listBox)
    S = getS(fig);
    sel = listBox.Value;
    tok = regexp(sel, '#(\d+)', 'tokens', 'once');
    if isempty(tok)
        setStatus(fig, '请选择要移除的 IV。');
        return;
    end

    rmId = str2double(tok{1});
    idx = find(arrayfun(@(v) v.id==rmId, S.vehicles), 1);
    if isempty(idx)
        setStatus(fig, sprintf('未找到 IV #%d。', rmId));
        return;
    end

    S.vehicles(idx) = [];
    if isvalid(removeFig)
        delete(removeFig);
    end
    S.removeFig = [];
    setS(fig, S);
    refreshDisplay(fig);
    updateIVDropdown(fig);
    setStatus(fig, sprintf('IV #%d 已移除。', rmId));
end

function onAngleChanged(fig, src)
    S = getS(fig);
    S.handles.angleValue.Text = sprintf('当前: %.0f°', src.Value);
    % 如果有选中的车辆，更新其角度并重绘
    if ~isempty(S.vehicles)
        sel = S.handles.ivDropdown.Value;
        tok = regexp(sel, '#(\d+)', 'tokens', 'once');
        if ~isempty(tok)
            id = str2double(tok{1});
            idx = find(arrayfun(@(v) v.id==id, S.vehicles), 1);
            if ~isempty(idx)
                S.vehicles(idx).angle = src.Value;
                setS(fig, S);
                refreshDisplay(fig);
            end
        end
    end
    end

function onIVDropdownChanged(fig)
%ONIVDROPDOWNCHANGED  切换下拉选中车辆时同步角度滑条与标签
    S = getS(fig);
    sel = S.handles.ivDropdown.Value;
    tok = regexp(sel, '#(\d+)', 'tokens', 'once');
    if isempty(tok), return; end
    vid = str2double(tok{1});
    idx = find(arrayfun(@(v) v.id==vid, S.vehicles), 1);
    if isempty(idx), return; end
    ang = S.vehicles(idx).angle;
    S.handles.angleSlider.Value = ang;
    S.handles.angleValue.Text = sprintf('当前: %.0f°', ang);
end

function onBtnReportIV(fig)
    S = getS(fig);
    if isempty(S.vehicles)
        setStatus(fig, '无车辆。');
        return;
    end
    lines = cell(numel(S.vehicles),1);
    for i = 1:numel(S.vehicles)
        [wx, wy] = px2world(fig, S.vehicles(i).cx, S.vehicles(i).cy);
        lines{i} = sprintf('车辆 #%d: 位置(%.1f, %.1f)m  朝向 %.0f°', ...
                           S.vehicles(i).id, wx, wy, S.vehicles(i).angle);
    end
    msg = strjoin(lines, newline);
    uialert(fig, msg, '所有车辆位置报告');
    setStatus(fig, sprintf('已报告 %d 辆车的位置。', numel(S.vehicles)));
end

%% ====================================================================
%   OR3 车头朝向相关回调
%% ====================================================================
function onBtnOR3(fig)
%ONBTNOR3  打开 OR3 车辆朝向设置弹窗
    S = getS(fig);
    if isfield(S, 'or3Fig') && ~isempty(S.or3Fig) && isvalid(S.or3Fig)
        figure(S.or3Fig);
        return;
    end
    or3Fig = uifigure('Name', 'OR3 车辆朝向工具', ...
                      'Position', [160 160 300 260], ...
                      'Resize', 'off');
    setappdata(or3Fig, 'mainFig', fig);

    gl = uigridlayout(or3Fig, [7 1]);
    gl.RowHeight = repmat({'fit'}, 7, 1);
    gl.ColumnWidth = {'1x'};

    r = 0;
    function c = addC(type, rowIdx, varargin)
        c = feval(['ui' type], gl, varargin{:});
        c.Layout.Row = rowIdx; c.Layout.Column = 1;
    end

    r = r + 1;
    addC('label', r, 'Text', 'OR3 车辆朝向工具', ...
         'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    r = r + 1;
    addC('label', r, 'Text', '──── 功能说明 ────', 'FontSize', 11, 'FontWeight', 'bold');
    r = r + 1;
    addC('label', r, 'Text', '自动对齐：加载车辆时自动与道路走向对齐。', ...
         'FontSize', 9, 'WordWrap', 'on');
    r = r + 1;
    addC('label', r, 'Text', '车头朝上：地图围绕选定车辆旋转，使车头始终指向上方。', ...
         'FontSize', 9, 'WordWrap', 'on');
    r = r + 1;
    addC('label', r, 'Text', '──── 操作 ────', 'FontSize', 11, 'FontWeight', 'bold');
    r = r + 1;
    addC('button', r, 'Text', '对齐到道路（当前车辆）', ...
         'ButtonPushedFcn', @(~,~) onBtnAlignCurrent(fig, or3Fig));
    r = r + 1;
    addC('button', r, 'Text', '关闭', ...
         'ButtonPushedFcn', @(~,~) close(or3Fig));

    S = getS(fig);
    S.or3Fig = or3Fig;
    setappdata(fig, 'S', S);
    set(or3Fig, 'CloseRequestFcn', @(~,~) close(or3Fig));
end

function onBtnAlignCurrent(fig, or3Fig)
%ONBTNALIGNCURRENT  将当前选中车辆的角度对齐到最近道路方向
    S = getS(fig);
    if isempty(S.vehicles)
        uialert(or3Fig, '当前没有已加载的车辆。', '提示');
        return;
    end
    sel = S.handles.ivDropdown.Value;
    tok = regexp(sel, '#(\d+)', 'tokens', 'once');
    if isempty(tok)
        uialert(or3Fig, '请先在下拉列表中选中一辆车辆。', '提示');
        return;
    end
    vid = str2double(tok{1});
    idx = find(arrayfun(@(v) v.id==vid, S.vehicles), 1);
    if isempty(idx), return; end
    newAngle = or3_auto_align('findAngle', fig, S.vehicles(idx).cx, S.vehicles(idx).cy);
    S.vehicles(idx).angle = newAngle;
    if S.headUpMode
        S.headUpAngle = newAngle;
    end
    setS(fig, S);
    refreshDisplay(fig);
    if isfield(S.handles,'angleSlider') && isvalid(S.handles.angleSlider)
        S.handles.angleSlider.Value = newAngle;
    end
    setStatus(fig, sprintf('车辆 #%d 朝向已对齐至 %.1f°', vid, newAngle));
end

function onHeadUpToggled(fig, src)
%ONHEADUPTOGGLED  "车头始终朝上"复选框状态改变
    S = getS(fig);
    S.headUpMode = src.Value;
    if S.headUpMode
        % 记录当前选定车辆的角度用于 head-up 旋转
        if ~isempty(S.vehicles) && isfield(S.handles,'ivDropdown') && isvalid(S.handles.ivDropdown)
            sel = S.handles.ivDropdown.Value;
            tok = regexp(sel, '#(\d+)', 'tokens', 'once');
            if ~isempty(tok)
                vid = str2double(tok{1});
                idx = find(arrayfun(@(v) v.id==vid, S.vehicles), 1);
                if ~isempty(idx)
                    S.headUpAngle = S.vehicles(idx).angle;
                end
            end
        end
        setStatus(fig, '车头朝上模式已启用：地图将围绕选定车辆旋转。');
    else
        setStatus(fig, '车头朝上模式已关闭。');
    end
    setS(fig, S);
    refreshDisplay(fig);
end

%% ====================================================================
%   测量功能（步骤 F）
%% ====================================================================
function onBtnMeasure2(fig)
    S = getS(fig);
    S.mode = 'measure2';
    S.measurePts = zeros(0,2);
    setS(fig, S);
    setStatus(fig, '两点测距：请点击第一个点。');
    S.handles.measureLabel.Text = '距离: ---';
end

function onBtnTrack(fig)
    S = getS(fig);
    S.mode = 'track';
    S.measurePts = zeros(0,2);
    setS(fig, S);
    setStatus(fig, '轨迹测量：连续点击多个点，右键结束并显示总长度。');
    S.handles.measureLabel.Text = '长度: 0.00 m';
end

function onBtnClearMeasure(fig)
    S = getS(fig);
    S.mode = 'idle';
    S.measurePts = zeros(0,2);
    setS(fig, S);
    refreshDisplay(fig);   % 恢复到不含测量标记的视图
    setStatus(fig, '测量标记已清除。');
    S.handles.measureLabel.Text = '距离: ---';
end

function handleMeasure2Click(fig, col, row)
    S = getS(fig);
    S.measurePts(end+1, :) = [col, row];   %#ok<AGROW>
    nPts = size(S.measurePts, 1);
    if nPts == 1
        setS(fig, S);
        drawMeasurement(fig);
        setStatus(fig, '已选第一点，请点击第二个点。');
    elseif nPts == 2
        setS(fig, S);
        drawMeasurement(fig);
        d = norm(S.measurePts(2,:) - S.measurePts(1,:)) * S.scale;
        S.handles.measureLabel.Text = sprintf('距离: %.2f m', d);
        S.mode = 'idle';
        setS(fig, S);
        setStatus(fig, sprintf('两点距离: %.2f m', d));
    end
end

function handleTrackClick(fig, col, row)
    S = getS(fig);
    selType = get(fig, 'SelectionType');
    if strcmp(selType, 'alt')   % 右键结束
        S.mode = 'idle';
        setS(fig, S);
        totalLen = computeTrackLength(S.measurePts, S.scale);
        S.handles.measureLabel.Text = sprintf('长度: %.2f m', totalLen);
        setStatus(fig, sprintf('轨迹完成: %d 点, 总长 %.2f m', ...
                  size(S.measurePts,1), totalLen));
        return;
    end
    % 左键追加
    S.measurePts(end+1, :) = [col, row];   %#ok<AGROW>
    setS(fig, S);
    drawMeasurement(fig);
    totalLen = computeTrackLength(S.measurePts, S.scale);
    S.handles.measureLabel.Text = sprintf('长度: %.2f m', totalLen);
    setStatus(fig, sprintf('轨迹第 %d 点, 当前总长 %.2f m（右键结束）', ...
              size(S.measurePts,1), totalLen));
end

function len = computeTrackLength(pts, scale)
%COMPUTETRACKLENGTH  计算折线总长度（米）
    len = 0;
    for i = 2:size(pts,1)
        len = len + norm(pts(i,:) - pts(i-1,:)) * scale;
    end
end

function drawMeasurement(fig)
%DRAWMEASUREMENT  在地图上绘制测量点+连线（青色），叠加在复合图上并应用旋转
    S = getS(fig);
    if isempty(S.mapOrigin), return; end
    % 1. 先构建复合图（原图+骨架+车辆）
    map = buildBaseMap(fig);
    [H, W, ~] = size(map);
    % 2. 叠加测量标记（青色连线 + 品红节点）
    pts = S.measurePts;
    if size(pts,1) >= 2
        for i = 2:size(pts,1)
            pxs = bresenham(pts(i-1,1), pts(i-1,2), pts(i,1), pts(i,2));
            for k = 1:size(pxs,1)
                map = stampSquare(map, pxs(k,1), pxs(k,2), 1, uint8([0 220 220]), W, H);
            end
        end
    end
    for i = 1:size(pts,1)
        map = stampSquare(map, pts(i,1), pts(i,2), 2, uint8([220 0 220]), W, H);
    end
    % 3. 应用旋转（与 refreshDisplay 一致的逻辑）
    if S.headUpMode
        vAngle = S.headUpAngle;
        vcx = S.mapW / 2;  vcy = S.mapH / 2;
        if ~isempty(S.vehicles)
            sel = S.handles.ivDropdown.Value;
            tok = regexp(sel, '#(\d+)', 'tokens', 'once');
            if ~isempty(tok)
                vid = str2double(tok{1});
                idx = find(arrayfun(@(v) v.id==vid, S.vehicles), 1);
                if ~isempty(idx)
                    vAngle = S.vehicles(idx).angle;
                    vcx = S.vehicles(idx).cx;
                    vcy = S.vehicles(idx).cy;
                end
            end
        end
        S.mapDisplay = or3_auto_align('rotateAround', map, vcx, vcy, headUpRotation(vAngle));
        S.rotSize    = [size(S.mapDisplay,1), size(S.mapDisplay,2)];
        S.rotCX      = [];
        S.rotCY      = [];
        S.headUpCX   = vcx;
        S.headUpCY   = vcy;
    elseif S.rotDeg ~= 0
        if isempty(S.rotCX) || isempty(S.rotCY)
            S.rotCX = (S.mapW + 1) / 2;
            S.rotCY = (S.mapH + 1) / 2;
        end
        S.mapDisplay = rotateMapAroundPoint(map, S.rotCX, S.rotCY, S.rotDeg);
        S.rotSize = [size(S.mapDisplay,1), size(S.mapDisplay,2)];
        S.viewCenter = mapOriginalPointToDisplay(S, S.rotCX, S.rotCY);
    else
        S.mapDisplay = map;
        S.rotSize = [];
        S.rotCX = [];
        S.rotCY = [];
    end
    setS(fig, S);
    refreshView(fig);
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

function onZoomChanged(fig, src)
    S = getS(fig);
    S.viewZoom = max(1, src.Value);
    S.viewCenter = [mean(S.ax.XLim), mean(S.ax.YLim)];
    if isfield(S.handles,'zoomLabel') && isvalid(S.handles.zoomLabel)
        S.handles.zoomLabel.Text = sprintf('显示缩放: %.1fx', S.viewZoom);
    end
    setS(fig, S);
    applyViewLimits(fig);
end

function onResetView(fig)
    S = getS(fig);
    S.viewZoom = 1;
    S.viewCenter = [];
    if isfield(S.handles,'zoomSlider') && isvalid(S.handles.zoomSlider)
        S.handles.zoomSlider.Value = 1;
    end
    if isfield(S.handles,'zoomLabel') && isvalid(S.handles.zoomLabel)
        S.handles.zoomLabel.Text = '显示缩放: 1.0x';
    end
    setS(fig, S);
    applyViewLimits(fig);
end


%% ====================================================================
%   旋转地图（占位回调，步骤 E 实现）
%% ====================================================================
function onRotChanged(fig, src)
%ONROTCHANGED  地图旋转回调（滑条）；对完整叠加图(地图+骨架+车辆)做反向映射旋转
    deg = round(src.Value);
    S = getS(fig);
    if isempty(S.mapOrigin), return; end
    if ~S.headUpMode
        viewCenterD = getCurrentDisplayCenter(S);
        anchor = mapDisplayPointToOriginal(S, viewCenterD(1), viewCenterD(2));
        if ~isempty(anchor)
            S.rotCX = anchor(1);
            S.rotCY = anchor(2);
        elseif isempty(S.rotCX) || isempty(S.rotCY)
            S.rotCX = (S.mapW + 1) / 2;
            S.rotCY = (S.mapH + 1) / 2;
        end
    end
    % 同步滑条与标签
    src.Value = deg;
    if isfield(S.handles,'rotLabel') && isvalid(S.handles.rotLabel)
        S.handles.rotLabel.Text = sprintf('旋转角度 (度): %.0f', deg);
    end
    S.rotDeg = deg;
    if deg ~= 0 && S.viewZoom < 1.25
        S.viewZoom = 1.25;
        S.viewCenter = [];
        if isfield(S.handles,'zoomSlider') && isvalid(S.handles.zoomSlider)
            S.handles.zoomSlider.Value = S.viewZoom;
        end
        if isfield(S.handles,'zoomLabel') && isvalid(S.handles.zoomLabel)
            S.handles.zoomLabel.Text = sprintf('显示缩放: %.1fx', S.viewZoom);
        end
    end
    if deg == 0 && ~S.headUpMode
        S.rotCX = [];
        S.rotCY = [];
    end
    setS(fig, S);
    % drawAllVehicles 会构建复合图并按 rotDeg 旋转（保证骨架/车辆一起转、不丢失）
    refreshDisplay(fig);
    setStatus(fig, sprintf('地图已旋转 %.0f°', deg));
end



function out = rotateMapAroundPoint(img, cx, cy, deg)
%ROTATEMAPAROUNDPOINT  手搓图像绕任意点旋转（反向映射 + 最近邻采样）
    [H, W, ~] = size(img);
    th = deg * pi / 180;
    c = cos(th); s = sin(th);

    % 1. 计算旋转后新画布的外接尺寸
    [newH, newW, shiftCol, shiftRow] = getRotationCanvasInfo(W, H, cx, cy, deg);
    out = uint8(255 * ones(newH, newW, 3));

    % 3. 向量化反向映射（避免慢速双重循环）
    [rowGrid, colGrid] = ndgrid(1:newH, 1:newW);
    rotX = shiftCol + colGrid(:) - 1;
    rotY = shiftRow + rowGrid(:) - 1;
    xRot = rotX - cx;
    yRot = rotY - cy;
    % 反向旋转（用 -th）：将新图坐标映射回原图坐标
    xOld =  xRot*c + yRot*s + cx;
    yOld = -xRot*s + yRot*c + cy;
    rOld = round(yOld);
    cOld = round(xOld);
    % 4. 有效区域掩膜
    valid = rOld>=1 & rOld<=H & cOld>=1 & cOld<=W;
    idx = find(valid);
    for ch = 1:3
        tmp = out(:,:,ch);
        tmp2 = img(:,:,ch);
        tmp(idx) = tmp2(rOld(idx) + (cOld(idx)-1)*H);
        out(:,:,ch) = tmp;
    end
end

function [newH, newW, shiftCol, shiftRow] = getRotationCanvasInfo(W, H, cx, cy, deg)
    th = deg * pi / 180;
    c = cos(th);
    s = sin(th);
    corners = [0.5 0.5; W + 0.5 0.5; W + 0.5 H + 0.5; 0.5 H + 0.5];
    centered = corners - [cx cy];
    rotCorners = centered * [c -s; s c]' + [cx cy];
    shiftCol = min(rotCorners(:,1));
    shiftRow = min(rotCorners(:,2));
    newW = ceil(max(rotCorners(:,1)) - shiftCol);
    newH = ceil(max(rotCorners(:,2)) - shiftRow);
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
%REFRESHVIEW  把当前 mapDisplay 显示到 axes（按旋转后尺寸设定坐标范围）
    S = getS(fig);
    if isempty(S.mapDisplay), return; end
    [dH, dW, ~] = size(S.mapDisplay);
    imshow(S.mapDisplay, 'Parent', S.ax);
    axis(S.ax, 'image');
    % 记录显示尺寸，供 getPointerOnAxes 做边界判定与反旋转
    S = getS(fig);
    S.dispH = dH; S.dispW = dW;
    setS(fig, S);
    applyViewLimits(fig);
end

function applyViewLimits(fig)
    S = getS(fig);
    if S.dispW <= 0 || S.dispH <= 0, return; end
    z = max(1, S.viewZoom);
    if isempty(S.viewCenter)
        center = [(S.dispW + 1) / 2, (S.dispH + 1) / 2];
    else
        center = S.viewCenter;
    end
    halfW = S.dispW / (2 * z);
    halfH = S.dispH / (2 * z);
    xlim = clampWindow([center(1)-halfW, center(1)+halfW], 0.5, S.dispW + 0.5);
    ylim = clampWindow([center(2)-halfH, center(2)+halfH], 0.5, S.dispH + 0.5);
    set(S.ax, 'XLim', xlim, 'YLim', ylim, 'YDir', 'reverse');
    S.viewCenter = [mean(xlim), mean(ylim)];
    setS(fig, S);
end

function lim = clampWindow(lim, lo, hi)
    width = lim(2) - lim(1);
    fullWidth = hi - lo;
    if width >= fullWidth
        lim = [lo hi];
    elseif lim(1) < lo
        lim = [lo lo + width];
    elseif lim(2) > hi
        lim = [hi - width hi];
    end
end

function ok = isPointerInDisplay(fig, ax)
    S = getS(fig);
    ok = false;
    if ~isgraphics(ax), return; end
    cp = get(ax, 'CurrentPoint');
    colD = cp(1,1); rowD = cp(1,2);
    ok = colD >= 1 && colD <= S.dispW && rowD >= 1 && rowD <= S.dispH;
end

function pt = getPointerOnAxes(fig, ax)
%GETPOINTERONAXES  返回鼠标在【原始地图】坐标系下的 [col, row]
%  若当前处于旋转态，先把鼠标点(显示坐标)反旋转回原图坐标，保证下游逻辑一致。
    pt = [];
    if ~isgraphics(ax), return; end
    cp = get(ax, 'CurrentPoint');
    if isempty(cp), return; end
    colD = cp(1,1); rowD = cp(1,2);   % 显示图中的列/行
    S = getS(fig);
    % 边界判定用显示图尺寸
    if colD < 1 || colD > S.dispW || rowD < 1 || rowD > S.dispH
        return;
    end
    pt = mapDisplayPointToOriginal(S, colD, rowD);
end

function center = getCurrentDisplayCenter(S)
    if isempty(S.viewCenter)
        center = [(S.dispW + 1) / 2, (S.dispH + 1) / 2];
    else
        center = S.viewCenter;
    end
end

function pt = mapDisplayPointToOriginal(S, colD, rowD)
    pt = [];
    if S.headUpMode && ~isempty(S.headUpCX)
        deg = headUpRotation(S.headUpAngle);
        cx0 = S.headUpCX;
        cy0 = S.headUpCY;
    elseif ~isempty(S.rotSize) && S.rotDeg ~= 0 && ~isempty(S.rotCX) && ~isempty(S.rotCY)
        deg = S.rotDeg;
        cx0 = S.rotCX;
        cy0 = S.rotCY;
    else
        if colD < 1 || colD > S.mapW || rowD < 1 || rowD > S.mapH
            return;
        end
        pt = [colD rowD];
        return;
    end
    th = deg * pi / 180;
    [~, ~, shiftCol, shiftRow] = getRotationCanvasInfo(S.mapW, S.mapH, cx0, cy0, deg);
    rotCol = shiftCol + colD - 1;
    rotRow = shiftRow + rowD - 1;
    xRot = rotCol - cx0;
    yRot = rotRow - cy0;
    colO = xRot * cos(th) + yRot * sin(th) + cx0;
    rowO = -xRot * sin(th) + yRot * cos(th) + cy0;
    if colO < 1 || colO > S.mapW || rowO < 1 || rowO > S.mapH
        return;
    end
    pt = [colO rowO];
end

function pt = mapOriginalPointToDisplay(S, col, row)
    pt = [];
    if S.headUpMode && ~isempty(S.headUpCX)
        deg = headUpRotation(S.headUpAngle);
        cx0 = S.headUpCX;
        cy0 = S.headUpCY;
    elseif ~isempty(S.rotSize) && S.rotDeg ~= 0 && ~isempty(S.rotCX) && ~isempty(S.rotCY)
        deg = S.rotDeg;
        cx0 = S.rotCX;
        cy0 = S.rotCY;
    else
        if col < 1 || col > S.mapW || row < 1 || row > S.mapH
            return;
        end
        pt = [col row];
        return;
    end
    th = deg * pi / 180;
    [~, ~, shiftCol, shiftRow] = getRotationCanvasInfo(S.mapW, S.mapH, cx0, cy0, deg);
    x = col - cx0;
    y = row - cy0;
    rotCol = x * cos(th) - y * sin(th) + cx0;
    rotRow = x * sin(th) + y * cos(th) + cy0;
    pt = [rotCol - shiftCol + 1, rotRow - shiftRow + 1];
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

%% ====================================================================
%   几何 / 图形算法（手写）
%   ptToSegDist / genRoadMask 已迁移到 or1_skeleton.m
%% ====================================================================
function pts = bresenham(x0, y0, x1, y1)
%BRESENHAM  经典 Bresenham 直线算法，返回线上所有像素 [col row]
    x0 = round(x0); y0 = round(y0); x1 = round(x1); y1 = round(y1);
    dx = abs(x1 - x0); dy = abs(y1 - y0);
    sx = sign(x1 - x0); sy = sign(y1 - y0);
    if sx == 0, sx = 1; end
    if sy == 0, sy = 1; end
    err = dx - dy;
    pts = zeros(0, 2);
    while true
        pts(end+1, :) = [x0, y0];   %#ok<AGROW>
        if x0 == x1 && y0 == y1, break; end
        e2 = 2 * err;
        if e2 > -dy
            err = err - dy;
            x0 = x0 + sx;
        end
        if e2 < dx
            err = err + dx;
            y0 = y0 + sy;
        end
    end
end
