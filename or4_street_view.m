function varargout = or4_street_view(action, mainFig, varargin)
%OR4_STREET_VIEW  OR4 虚拟街景生成（弹出窗口 + 光线投射渲染）
%
%  用法：
%    or4_street_view('open', mainFig)                         打开弹窗
%    or4_street_view('click', mainFig, col, row)              主窗口鼠标点击（设置相机位置）
%    or4_street_view('getCam', mainFig)                       返回当前相机参数结构体
%    or4_street_view('drawCam', mainFig, mapImage)             在 mapImage 上叠加相机标记
%
%  渲染原理（光线投射，从备份 streetViewCameraUI.m 迁移适配）：
%    对输出图每个像素，计算一条从相机出发的光线，求其与地面（z=0）的交点，
%    再将该交点的世界坐标映射回原图像素位置进行采样。

    switch action
        case 'open'
            do_open(mainFig);
        case 'click'
            selType = '';
            if numel(varargin) >= 3
                selType = varargin{3};
            end
            do_click(mainFig, varargin{1}, varargin{2}, selType);
        case 'getCam'
            varargout{1} = doGetCam(mainFig);
        case 'drawCam'
            varargout{1} = doDrawCam(mainFig, varargin{1});
    end
end


%% ====================================================================
%   打开弹窗
%% ====================================================================
function do_open(mainFig)
    S = getappdata(mainFig, 'S');

    % 若弹窗已存在则前置
    if isfield(S, 'or4Fig') && ~isempty(S.or4Fig) && isvalid(S.or4Fig)
        figure(S.or4Fig);
        return;
    end

    % ---- 默认相机参数 ----
    cam.realX      = S.mapW / 2 * S.scale;   % 地图中心 X（米）
    cam.realY      = S.mapH / 2 * S.scale;   % 地图中心 Y（米）
    cam.height     = 3;                       % 相机离地高度（米，低高度减缓距离增长）
    cam.yawDegree  = 0;                       % 朝向角：0°=北，90°=东
    cam.pitchDegree = 10;                     % 俯仰角（向下为正，足以看到近处地面）
    cam.focalPixel = 280;                     % 焦距（像素）
    cam.viewDist   = 200;                     % FOV 锥形在地图上显示长度（米）
    cam.maxDist    = 1000;                    % 最大可见距离（米）

    % 若已有车辆，用第一辆车的位置和朝向
    if ~isempty(S.vehicles)
        v = S.vehicles(1);
        cam.realX = v.cx * S.scale;
        cam.realY = (S.mapH - v.cy) * S.scale;
        cam.yawDegree = mod(v.angle + 90, 360);   % 图像角 -> yaw（0°=北, 90°=东）
    end

    viewW = 520;
    viewH = 360;

    % ---- 创建弹窗 ----
    or4Fig = uifigure('Name', 'OR4 虚拟街景', ...
                      'Position', [120 120 900 640], ...
                      'Resize', 'on');
    setappdata(or4Fig, 'mainFig', mainFig);

    gl = uigridlayout(or4Fig, [1 2]);
    gl.ColumnWidth = {'1x', '2x'};
    gl.RowHeight = {'1x'};

    % 左面板：控制
    leftPanel = uipanel(gl, 'Title', '');
    leftPanel.Layout.Row = 1;
    leftPanel.Layout.Column = 1;
    leftGl = uigridlayout(leftPanel, [22 2]);
    leftGl.RowHeight = repmat({'fit'}, 22, 1);
    leftGl.ColumnWidth = {'1x', '1x'};

    r = 0;
    function c = addL(type, rowIdx, colIdx, varargin)
        if strcmp(type, 'editfield')
            c = uieditfield(leftGl, 'numeric', varargin{:});
        else
            c = feval(['ui' type], leftGl, varargin{:});
        end
        c.Layout.Row = rowIdx;
        c.Layout.Column = colIdx;
    end
    function c = addSpan(type, rowIdx, varargin)
        c = feval(['ui' type], leftGl, varargin{:});
        c.Layout.Row = rowIdx;
        c.Layout.Column = [1 2];
    end

    % 标题
    r = r + 1;
    addSpan('label', r, 'Text', '虚拟街景 (OR4)', ...
            'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    % 车辆快速选取
    r = r + 1;
    addL('label', r, 1, 'Text', '用车辆:', 'FontSize', 9);
    vehItems = {'(手动设置)'};
    if ~isempty(S.vehicles)
        for i = 1:numel(S.vehicles)
            vehItems{end+1} = sprintf('#%d', S.vehicles(i).id);   %#ok<AGROW>
        end
    end
    vehDrop = addL('dropdown', r, 2, 'Items', vehItems, 'Value', vehItems{1}, ...
                   'ValueChangedFcn', @(s,~) onVehSelected(or4Fig, s));

    % 相机位置
    r = r + 1;
    addSpan('label', r, 'Text', '── 相机位置 ──', 'FontSize', 10, 'FontWeight', 'bold');
    r = r + 1;
    addL('label', r, 1, 'Text', 'X (米):', 'FontSize', 9);
    xField = addL('editfield', r, 2, 'Value', cam.realX, 'ValueChangedFcn', @(s,~) onParamChanged(or4Fig));
    r = r + 1;
    addL('label', r, 1, 'Text', 'Y (米):', 'FontSize', 9);
    yField = addL('editfield', r, 2, 'Value', cam.realY, 'ValueChangedFcn', @(s,~) onParamChanged(or4Fig));
    r = r + 1;
    addL('label', r, 1, 'Text', '高度 (米):', 'FontSize', 9);
    hField = addL('editfield', r, 2, 'Value', cam.height, 'ValueChangedFcn', @(s,~) onParamChanged(or4Fig));

    % 相机姿态
    r = r + 1;
    addSpan('label', r, 'Text', '── 相机姿态 ──', 'FontSize', 10, 'FontWeight', 'bold');
    r = r + 1;
    addL('label', r, 1, 'Text', '朝向 yaw (0°=北, 顺时针):', 'FontSize', 9);
    yawField = addL('editfield', r, 2, 'Value', cam.yawDegree, 'ValueChangedFcn', @(s,~) onParamChanged(or4Fig));
    r = r + 1;
    addL('label', r, 1, 'Text', '俯仰 pitch:', 'FontSize', 9);
    pitchField = addL('editfield', r, 2, 'Value', cam.pitchDegree, 'ValueChangedFcn', @(s,~) onParamChanged(or4Fig));
    r = r + 1;
    addL('label', r, 1, 'Text', '焦距 (px):', 'FontSize', 9);
    focalField = addL('editfield', r, 2, 'Value', cam.focalPixel, 'ValueChangedFcn', @(s,~) onParamChanged(or4Fig));

    % yaw 微调按钮
    r = r + 1;
    addL('button', r, 1, 'Text', 'yaw -15', ...
         'ButtonPushedFcn', @(~,~) nudgeYaw(or4Fig, -15));
    addL('button', r, 2, 'Text', 'yaw +15', ...
         'ButtonPushedFcn', @(~,~) nudgeYaw(or4Fig, 15));

    % 操作按钮
    r = r + 1;
    addSpan('label', r, 'Text', '── 操作 ──', 'FontSize', 10, 'FontWeight', 'bold');
    r = r + 1;
    btnPick = addSpan('button', r, 'Text', '在地图上点击设置位置', ...
                      'ButtonPushedFcn', @(~,~) startPickMode(or4Fig));
    r = r + 1;
    btnRender = addSpan('button', r, 'Text', '生成街景', ...
                        'ButtonPushedFcn', @(~,~) onRender(or4Fig));

    % 状态信息
    r = r + 1;
    infoLabel = addSpan('label', r, 'Text', '点击"在地图上点击设置位置"或直接修改参数后生成。', ...
                        'FontSize', 8, 'FontAngle', 'italic', 'WordWrap', 'on');

    % 关闭按钮
    r = r + 1;
    addSpan('button', r, 'Text', '关闭', ...
            'ButtonPushedFcn', @(~,~) close(or4Fig));

    % 右面板：街景显示
    rightPanel = uipanel(gl, 'Title', '');
    rightPanel.Layout.Row = 1;
    rightPanel.Layout.Column = 2;
    viewAx = uiaxes(rightPanel, 'Units', 'normalized', 'Position', [0 0 1 1]);
    set(viewAx, 'XTick', [], 'YTick', [], 'Box', 'off', ...
                'XColor', 'none', 'YColor', 'none');
    viewAx.Toolbar.Visible = 'off';

    % 存储弹窗句柄
    or4 = struct();
    or4.vehDrop     = vehDrop;
    or4.xField      = xField;
    or4.yField      = yField;
    or4.hField      = hField;
    or4.yawField    = yawField;
    or4.pitchField  = pitchField;
    or4.focalField  = focalField;
    or4.infoLabel   = infoLabel;
    or4.viewAx      = viewAx;
    or4.cam         = cam;
    or4.viewW       = viewW;
    or4.viewH       = viewH;

    S.or4Fig = or4Fig;
    S.or4    = or4;
    setappdata(mainFig, 'S', S);

    set(or4Fig, 'CloseRequestFcn', @(~,~) do_close(mainFig, or4Fig));

    % 仅在默认相机点有效时初始渲染，避免打开窗口就弹错误
    [camCol, camRow] = worldToPixel(cam.realX, cam.realY, S.scale, S.mapH);
    if isRoadPointForUI(S.mapOrigin, S.basicRoadMask, S.roadMask, camRow, camCol)
        onRender(or4Fig);
    else
        S.or4.infoLabel.Text = '请点击下方"在地图上点击设置位置"按钮后选择道路点，或从"用车辆"下拉选一辆已加载车辆。';
        setappdata(mainFig, 'S', S);
    end
end


%% ====================================================================
%   关闭弹窗
%% ====================================================================
function do_close(mainFig, or4Fig)
    S = getappdata(mainFig, 'S');
    if strcmp(S.mode, 'or4')
        S.mode = 'idle';
    end
    if isfield(S, 'or4Fig') && isvalid(S.or4Fig)
        delete(S.or4Fig);
    end
    S.or4Fig = [];
    S.or4    = [];
    setappdata(mainFig, 'S', S);
    S.fn.refresh(mainFig);
    S.fn.setStatus(mainFig, '街景工具已关闭。');
end


%% ====================================================================
%   主窗口鼠标点击（由 onMouseDown 的 'or4' case 调用）
%% ====================================================================
function do_click(mainFig, col, row, selType)
    S = getappdata(mainFig, 'S');
    rc = round(row); cc = round(col);
    if rc < 1 || rc > S.mapH || cc < 1 || cc > S.mapW, return; end
    if nargin >= 4 && ~isempty(selType) && strcmp(selType, 'alt')
        S.mode = 'idle';
        setappdata(mainFig, 'S', S);
        S.fn.setStatus(mainFig, 'OR4 选点已取消。');
        return;
    end

    if ~isRoadPointForUI(S.mapOrigin, S.basicRoadMask, S.roadMask, rc, cc)
        if isfield(S, 'or4Fig') && ~isempty(S.or4Fig) && isvalid(S.or4Fig)
            uialert(S.or4Fig, '该点不在道路上，不能设置 OR4 相机位置。', 'OR4 设置失败');
        end
        S.fn.setStatus(mainFig, 'OR4：请选择道路上的点设置相机。');
        return;
    end

    % 更新相机位置（像素 -> 世界坐标）
    wx = cc * S.scale;
    wy = (S.mapH - rc) * S.scale;

    if isfield(S, 'or4') && ~isempty(S.or4)
        S.or4.cam.realX = wx;
        S.or4.cam.realY = wy;
        S.or4.xField.Value = wx;
        S.or4.yField.Value = wy;
        setappdata(mainFig, 'S', S);
        onRender(S.or4Fig);
        S.fn.setStatus(mainFig, sprintf('OR4: 相机位置已设为 (%.1f, %.1f)m', wx, wy));
    end
end


%% ====================================================================
%   获取相机参数（供 main.m 叠加标记用）
%% ====================================================================
function cam = doGetCam(mainFig)
    S = getappdata(mainFig, 'S');
    if isfield(S, 'or4') && ~isempty(S.or4) && isfield(S.or4, 'cam')
        cam = readCamFromUI(S.or4Fig);
    else
        cam = [];
    end
end


%% ====================================================================
%   在主地图上绘制相机标记（返回标记图，供 main.m overlay）
%   mapImage：当前要画标记的地图矩阵（可以是已有骨架/车辆的复合图）
%% ====================================================================
function markedMap = doDrawCam(mainFig, mapImage)
    S = getappdata(mainFig, 'S');
    cam = doGetCam(mainFig);
    if isempty(cam)
        markedMap = mapImage;
        return;
    end
    markedMap = drawCameraOnMap(mapImage, cam, S.scale, S.mapW, S.mapH);
end


%% ====================================================================
%   弹窗内部回调
%% ====================================================================
function onVehSelected(or4Fig, src)
    mainFig = getappdata(or4Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    val = src.Value;
    if strcmp(val, '(手动设置)'), return; end
    tok = regexp(val, '#(\d+)', 'tokens', 'once');
    if isempty(tok), return; end
    vid = str2double(tok{1});
    idx = find(arrayfun(@(v) v.id==vid, S.vehicles), 1);
    if isempty(idx), return; end
    v = S.vehicles(idx);
    wx = v.cx * S.scale;
    wy = (S.mapH - v.cy) * S.scale;
    S.or4.cam.realX = wx;
    S.or4.cam.realY = wy;
    S.or4.cam.yawDegree = mod(v.angle + 90, 360);   % 图像角 -> yaw（0°=北, 90°=东）
    S.or4.xField.Value = wx;
    S.or4.yField.Value = wy;
    S.or4.yawField.Value = S.or4.cam.yawDegree;
    setappdata(mainFig, 'S', S);
    % 同步主窗口 IV 下拉选中
    targetStr = sprintf('#%d (%.0f,%.0f)', v.id, v.cx, v.cy);
    mainItems = S.handles.ivDropdown.Items;
    if any(strcmp(mainItems, targetStr))
        S.handles.ivDropdown.Value = targetStr;
    end
    onRender(or4Fig);
end

function onParamChanged(or4Fig)
    % 参数文本框改变时同步到 cam 结构体（不自动渲染，等用户点"生成街景"按钮）
    mainFig = getappdata(or4Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    cam = readCamFromUI(or4Fig);
    if ~isempty(cam)
        S.or4.cam = cam;
        setappdata(mainFig, 'S', S);
    end
    S.or4.infoLabel.Text = '参数已更新，请点击"生成街景"查看效果。';
end

function nudgeYaw(or4Fig, delta)
    mainFig = getappdata(or4Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    S.or4.cam.yawDegree = S.or4.cam.yawDegree + delta;
    S.or4.yawField.Value = S.or4.cam.yawDegree;
    setappdata(mainFig, 'S', S);
    onRender(or4Fig);
end

function startPickMode(or4Fig)
    mainFig = getappdata(or4Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    S.mode = 'or4';
    setappdata(mainFig, 'S', S);
    S.fn.setStatus(mainFig, 'OR4：请点击地图上的道路位置设置相机。');
end

function cam = readCamFromUI(or4Fig)
    mainFig = getappdata(or4Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    cam = S.or4.cam;
    cam.realX      = S.or4.xField.Value;
    cam.realY      = S.or4.yField.Value;
    cam.height     = S.or4.hField.Value;
    cam.yawDegree  = S.or4.yawField.Value;
    cam.pitchDegree = S.or4.pitchField.Value;
    cam.focalPixel = S.or4.focalField.Value;
end


%% ====================================================================
%   渲染街景（核心）
%% ====================================================================
function onRender(or4Fig)
    mainFig = getappdata(or4Fig, 'mainFig');
    S = getappdata(mainFig, 'S');
    cam = readCamFromUI(or4Fig);
    [camCol, camRow] = worldToPixel(cam.realX, cam.realY, S.scale, S.mapH);
    if ~isRoadPointForUI(S.mapOrigin, S.basicRoadMask, S.roadMask, camRow, camCol)
        S.or4.infoLabel.Text = '相机位置必须落在道路上。';
        setappdata(mainFig, 'S', S);
        uialert(or4Fig, '当前相机位置不在道路上，请重新选择道路点。', 'OR4 渲染失败');
        S.fn.setStatus(mainFig, 'OR4：当前相机位置不在道路上。');
        return;
    end
    S.or4.cam = cam;
    setappdata(mainFig, 'S', S);

    viewW = S.or4.viewW;
    viewH = S.or4.viewH;

    % 渲染虚拟视图（光线投射）
    viewImage = renderStreetView(S.mapOrigin, cam, viewH, viewW, S.scale, S.mapH);

    % 显示街景
    imshow(viewImage, 'Parent', S.or4.viewAx);
    axis(S.or4.viewAx, 'image');

    % 通过 main.m 的刷新函数更新主地图（refreshDisplay 会自动叠加相机标记）
    S.fn.refresh(mainFig);

    S.or4.infoLabel.Text = sprintf('相机: (%.0f,%.0f)m  yaw=%.0f pitch=%.0f h=%.0f  焦距=%dpx', ...
        cam.realX, cam.realY, cam.yawDegree, cam.pitchDegree, cam.height, cam.focalPixel);
end


%% ====================================================================
%   renderStreetView — 光线投射渲染虚拟街景（修复版）
%
%   原理：对输出图像每个像素，计算一条从相机出发的光线，
%   求其与地面（z=0）的交点，再反算原图上的采样位置。
%
%   使用虚拟相机高度（50m+）加较大俯仰角来保证街景覆盖合理范围。
%% ====================================================================
function viewImage = renderStreetView(mapImage, cam, viewH, viewW, scale, mapH)
    [right, up, forward] = getCameraBaseVectors(cam);
    cameraCenter = [cam.realX, cam.realY, cam.height];

    viewImage = uint8(zeros(viewH, viewW, 3));
    skyColor     = uint8([205 225 245]);   % 浅蓝天空
    outsideColor = uint8([235 235 235]);   % 浅灰（超出可见范围）

    [imgH, imgW, ~] = size(mapImage);

    for vRow = 1:viewH
        % 图像平面 Y 偏移（行号小=图像上方=世界远处）
        yPlane = viewH / 2 - vRow;

        for vCol = 1:viewW
            xPlane = vCol - viewW / 2;

            % 光线方向（相机坐标系）
            rayDir = cam.focalPixel * forward + xPlane * right + yPlane * up;

            % 光线朝上（或水平）→ 天空
            if rayDir(3) >= -1e-4
                viewImage(vRow, vCol, :) = skyColor;
                continue;
            end

            % 求与地面 z=0 的交点
            tGround = -cameraCenter(3) / rayDir(3);
            if tGround <= 0
                % 交点在地面以下 → 天空（理论不会出现，作为保护）
                viewImage(vRow, vCol, :) = skyColor;
                continue;
            end

            groundPt = cameraCenter + tGround * rayDir;

            % 世界坐标 → 像素坐标（与 px2world 一致的约定）
            mapCol = round(groundPt(1) / scale);
            mapRow = round(mapH - groundPt(2) / scale);

            dx = groundPt(1) - cam.realX;
            dy = groundPt(2) - cam.realY;
            distOnGround = sqrt(dx*dx + dy*dy);

            if distOnGround <= cam.maxDist && ...
               mapRow >= 1 && mapRow <= imgH && mapCol >= 1 && mapCol <= imgW
                viewImage(vRow, vCol, :) = mapImage(mapRow, mapCol, :);
            else
                viewImage(vRow, vCol, :) = outsideColor;
            end
        end
    end
end


%% ====================================================================
%   drawCameraOnMap — 在地图上绘制相机位置 + FOV 锥形
%% ====================================================================
function mapOut = drawCameraOnMap(mapImage, cam, scale, mapW, mapH)
    mapOut = mapImage;
    viewW = 520;   % 默认视图宽度（像素）
    % 相机位置像素坐标
    camCol = round(cam.realX / scale);
    camRow = round(mapH - cam.realY / scale);

    % 红色标记点
    mapOut = stampSq(mapOut, camCol, camRow, 5, uint8([255 0 0]), mapW, mapH);

    % 朝向线 + FOV 锥形（黄色）
    lineLen = cam.viewDist / scale;   % 显示长度（像素）
    yawRad  = cam.yawDegree * pi / 180;
    halfFov = atan( (viewW / 2) / cam.focalPixel );   % 由相机参数推导（S.or4.viewW 不可用时回退到 520）

    % 中线
    endCol = camCol + lineLen * sin(yawRad);
    endRow = camRow - lineLen * cos(yawRad);
    mapOut = drawLinePx(mapOut, camRow, camCol, round(endRow), round(endCol), ...
                        uint8([255 255 0]), 2, mapW, mapH);

    % 左边界
    leftAngle = yawRad - halfFov;
    lCol = camCol + lineLen * sin(leftAngle);
    lRow = camRow - lineLen * cos(leftAngle);
    mapOut = drawLinePx(mapOut, camRow, camCol, round(lRow), round(lCol), ...
                        uint8([255 255 0]), 1, mapW, mapH);

    % 右边界
    rightAngle = yawRad + halfFov;
    rCol = camCol + lineLen * sin(rightAngle);
    rRow = camRow - lineLen * cos(rightAngle);
    mapOut = drawLinePx(mapOut, camRow, camCol, round(rRow), round(rCol), ...
                        uint8([255 255 0]), 1, mapW, mapH);
end


%% ====================================================================
%   相机坐标系构建（从备份迁移，手写矩阵运算）
%% ====================================================================
function [rcw, tcw, rwc, twc] = getCameraTransforms(cam)
    pitch = cam.pitchDegree * pi / 180;
    yaw   = cam.yawDegree   * pi / 180;

    % 中间姿态法（Intermediate-Pose Approach）
    % Step 1: 绕 X 轴旋转 pitch
    R1 = [1, 0, 0;
          0, cos(pitch), -sin(pitch);
          0, sin(pitch),  cos(pitch)];

    % Step 2: 坐标轴翻转（相机 Y 向上 -> 世界 Z 向上）
    R2 = [1, 0, 0;
          0, 0, -1;
          0, 1,  0];

    % Step 3: 绕 Z 轴旋转 azimuth（az = pi - yaw）
    az = pi - yaw;
    R3 = [cos(az), -sin(az), 0;
          sin(az),  cos(az), 0;
          0,        0,       1];

    % Step 4: 平移到世界坐标
    T4 = [cam.realX; cam.realY; cam.height];

    % 组合变换：Rcw = R3 * R2 * R1，Tcw 逐级累加
    R = R3 * R2 * R1;
    rcw = R;
    tcw = T4;

    rwc = rcw';
    twc = -rwc * tcw;
end

function [right, up, forward] = getCameraBaseVectors(cam)
    [rcw, ~, ~, ~] = getCameraTransforms(cam);
    right   = rcw(:, 1)';   % 相机 X 轴（右）
    up      = rcw(:, 2)';   % 相机 Y 轴（上）
    forward = rcw(:, 3)';   % 相机 Z 轴（前/观察方向）
end

function [col, row] = worldToPixel(realX, realY, scale, mapH)
    col = realX / scale;
    row = mapH - realY / scale;
end


%% ====================================================================
%   手绘辅助函数（与 main.m 保持一致，此处独立一份避免跨文件依赖）
%% ====================================================================
function mapOut = stampSq(mapIn, cx, cy, radius, color, mapW, mapH)
    mapOut = mapIn;
    cc0 = round(cx); rr0 = round(cy);
    for dr = -radius:radius
        for dc = -radius:radius
            rr = rr0 + dr; cc = cc0 + dc;
            if cc >= 1 && cc <= mapW && rr >= 1 && rr <= mapH
                mapOut(rr, cc, :) = color;
            end
        end
    end
end

function mapOut = drawLinePx(mapIn, r1, c1, r2, c2, color, thickness, mapW, mapH)
    mapOut = mapIn;
    pts = bresenhamLocal(c1, r1, c2, r2);
    for k = 1:size(pts, 1)
        mapOut = stampSq(mapOut, pts(k,1), pts(k,2), thickness, color, mapW, mapH);
    end
end

function pts = bresenhamLocal(x0, y0, x1, y1)
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
