%TEST_OR5_POPUP  测试 OR5 路径规划（独立版，基于 RoadMask.jpg 栅格搜索）
%  覆盖：栅格 BFS 纯算法 + 最近道路像素吸附 + UI 工作流 + 性能
fprintf('========== OR5 Path Planning Test (grid, RoadMask) ==========\n');
try
    %% ---- A. 纯算法单元测试（人工栅格，不依赖 UI/真实图） ----
    % 十字形道路：行5 第2..9列 + 列5 第2..9行
    m = false(10, 10);
    m(5, 2:9) = true;
    m(2:9, 5) = true;
    % (5,2) -> (2,5)：走到交叉点(5,5)=3步，再上到(2,5)=3步，共6步
    [pr, pc, d] = gridBFS(m, 5, 2, 2, 5);
    assert(~isempty(pr) && d == 6, sprintf('cross path d=%g', d));
    assert(pr(1)==5 && pc(1)==2 && pr(end)==2 && pc(end)==5, 'cross endpoints wrong');
    fprintf('[OK] gridBFS cross: 6 steps\n');

    % 同点
    [pr0, pc0, d0] = gridBFS(m, 5, 5, 5, 5);
    assert(d0 == 0 && pr0==5 && pc0==5, 'same-point BFS wrong');
    fprintf('[OK] gridBFS same point: 0 steps\n');

    % 断开图：无路径
    m2 = false(10,10); m2(5,2)=true; m2(5,9)=true;
    [pr2, ~, d2] = gridBFS(m2, 5, 2, 5, 9);
    assert(isempty(pr2) && isinf(d2), 'disconnected should be inf');
    fprintf('[OK] gridBFS disconnected -> inf\n');

    % L 形道路验证回溯顺序连续且 4 连通
    m3 = false(10,10); m3(2,2:6)=true; m3(2:6,6)=true;
    [pr3, pc3, d3] = gridBFS(m3, 2, 2, 6, 6);
    assert(~isempty(pr3) && d3 == 8, sprintf('L-path d=%g', d3));
    ok = true;
    for i = 2:numel(pr3)
        if abs(pr3(i)-pr3(i-1)) + abs(pc3(i)-pc3(i-1)) ~= 1, ok = false; end
    end
    assert(ok, 'L-path not 4-connected');
    fprintf('[OK] gridBFS L-path: 8 steps, 4-connected\n');

    % 最近道路像素：m4 中道路为 (row=10,col=10) 和 (row=10,col=11)
    m4 = false(20,20); m4(10,10)=true; m4(10,11)=true;
    [r4, c4] = findNearestRoadPixel(m4, 8, 10);   % col=8 离 col=10(距2)比 col=11(距3)近
    assert(r4==10 && c4==10, sprintf('nearest pixel wrong: (%d,%d)', r4, c4));
    [r5, c5] = findNearestRoadPixel(m4, 14, 10);  % col=14 离 col=11(距3)比 col=10(距4)近
    assert(r5==10 && c5==11, sprintf('nearest pixel2 wrong: (%d,%d)', r5, c5));
    fprintf('[OK] findNearestRoadPixel\n');

    %% ---- B. UI 工作流测试（真实 RoadMask.jpg） ----
    fig = main();
    S = getappdata(fig, 'S');

    % 1. 打开 OR5（自动加载 RoadMask）
    or5_path_planning('open', fig);
    S = getappdata(fig, 'S');
    assert(isvalid(S.or5Fig) && isfield(S,'or5') && ~isempty(S.or5.roadMask), 'OR5 not ready');
    nRoad = sum(S.or5.roadMask(:));
    assert(nRoad > 1000, sprintf('road pixels too few: %d', nRoad));
    fprintf('[OK] OR5 opened, road loaded: %d pixels\n', nRoad);

    % 道路高亮可见（淡青色：G、B 偏高，R 偏低）
    cyanPx = nnz(S.mapDisplay(:,:,2)>120 & S.mapDisplay(:,:,3)>140 & S.mapDisplay(:,:,1)<100);
    assert(cyanPx > 0, 'road highlight not visible');
    fprintf('[OK] road highlighted: %d px\n', cyanPx);

    % 2. 找真实道路上的两个相近像素作起终点（保证连通且 BFS 快）
    [rr, cc] = find(S.or5.roadMask);
    H = S.mapH; W = S.mapW;
    p1R = 0; p1C = 0; nbrR = 0; nbrC = 0;
    for idx = 1:min(numel(rr), 8000)
        tr = rr(idx); tc = cc(idx);
        if tr>1 && S.or5.roadMask(tr-1,tc), p1R=tr; p1C=tc; nbrR=tr-1; nbrC=tc; break; end
        if tc>1 && S.or5.roadMask(tr,tc-1), p1R=tr; p1C=tc; nbrR=tr; nbrC=tc-1; break; end
        if tr<H && S.or5.roadMask(tr+1,tc), p1R=tr; p1C=tc; nbrR=tr+1; nbrC=tc; break; end
        if tc<W && S.or5.roadMask(tr,tc+1), p1R=tr; p1C=tc; nbrR=tr; nbrC=tc+1; break; end
    end
    assert(nbrR ~= 0, 'cannot find adjacent road pair');
    fprintf('[OK] adjacent road pair: (%d,%d)-(%d,%d)\n', p1R, p1C, nbrR, nbrC);

    % 3. 设置起点（点 p1，应吸附到 p1）
    S.or5.btnSetStart.ButtonPushedFcn(S.or5.btnSetStart, []);
    or5_path_planning('click', fig, p1C, p1R, 'normal');
    S = getappdata(fig, 'S');
    assert(S.or5.startPt(1)==p1C && S.or5.startPt(2)==p1R, ...
           sprintf('start snap wrong: got (%d,%d)', S.or5.startPt(1), S.or5.startPt(2)));
    fprintf('[OK] start snapped to (%d,%d)\n', p1C, p1R);

    % 4. 设置终点
    S.or5.btnSetEnd.ButtonPushedFcn(S.or5.btnSetEnd, []);
    or5_path_planning('click', fig, nbrC, nbrR, 'normal');
    S = getappdata(fig, 'S');
    assert(S.or5.endPt(1)==nbrC && S.or5.endPt(2)==nbrR, 'end snap wrong');
    fprintf('[OK] end snapped to (%d,%d)\n', nbrC, nbrR);

    % 5. 规划路径（相邻像素，1 步 = 1.7 m）
    tic;
    S.or5.btnPlan.ButtonPushedFcn(S.or5.btnPlan, []);
    elapsed = toc;
    S = getappdata(fig, 'S');
    assert(~isempty(S.or5.pathPx), 'no path for adjacent pixels');
    assert(S.or5.pathLen == S.scale, sprintf('adjacent pathLen=%g expected=%g', S.or5.pathLen, S.scale));
    assert(elapsed < 30, sprintf('BFS too slow: %.2f s', elapsed));
    greenPx = nnz(S.mapDisplay(:,:,2)>150 & S.mapDisplay(:,:,1)<80 & S.mapDisplay(:,:,3)<80);
    assert(greenPx > 0, 'green path not visible');
    fprintf('[OK] path planned: len=%.2f m, %.2f s, green=%d px\n', S.or5.pathLen, elapsed, greenPx);

    % 6. 远距离路径测试（验证性能 + bounding box/全图搜索）
    farIdx = find((cc-p1C).^2 + (rr-p1R).^2 > 300^2, 1);
    if ~isempty(farIdx)
        farR = rr(farIdx); farC = cc(farIdx);
        S = getappdata(fig, 'S');
        S.or5.endPt = [farC, farR];
        setappdata(fig, 'S', S);
        tic;
        S.or5.btnPlan.ButtonPushedFcn(S.or5.btnPlan, []);
        elapsed2 = toc;
        S = getappdata(fig, 'S');
        if ~isempty(S.or5.pathPx)
            fprintf('[OK] far path: %d px, %.2f m, %.2f s\n', ...
                size(S.or5.pathPx,1), S.or5.pathLen, elapsed2);
            assert(elapsed2 < 30, sprintf('far BFS too slow: %.2f s', elapsed2));
        else
            fprintf('[INFO] far pair not connected (different components), skipped\n');
        end
    end

    % 7. 旋转后路径保留
    S = getappdata(fig, 'S');
    S.handles.rotSlider.Value = 30;
    S.handles.rotSlider.ValueChangedFcn(S.handles.rotSlider, []);
    S = getappdata(fig, 'S');
    assert(~isempty(S.or5.pathPx), 'path lost after rotate');
    S.handles.rotSlider.Value = 0;
    S.handles.rotSlider.ValueChangedFcn(S.handles.rotSlider, []);
    fprintf('[OK] path preserved through rotate\n');

    % 8. 隐藏/显示道路高亮
    S = getappdata(fig, 'S');
    S.or5.btnToggleRoad.ButtonPushedFcn(S.or5.btnToggleRoad, []);
    S = getappdata(fig, 'S');
    assert(~S.or5.showRoad, 'showRoad should be false');
    S.or5.btnToggleRoad.ButtonPushedFcn(S.or5.btnToggleRoad, []);
    S = getappdata(fig, 'S');
    assert(S.or5.showRoad, 'showRoad should be true');
    fprintf('[OK] road highlight toggle\n');

    % 9. 清除路径
    S.or5.btnClear.ButtonPushedFcn(S.or5.btnClear, []);
    S = getappdata(fig, 'S');
    assert(isempty(S.or5.pathPx) && isempty(S.or5.startPt) && isempty(S.or5.endPt), 'clear failed');
    assert(~isempty(S.or5.roadMask), 'road should remain after clear');
    fprintf('[OK] path cleared, road kept\n');

    % 10. 关闭 OR5
    or5_path_planning('close', fig);
    S = getappdata(fig, 'S');
    assert(isempty(S.or5Fig) || ~isvalid(S.or5Fig), 'OR5 still open');
    assert(strcmp(S.mode,'idle'), 'mode not idle after close');
    fprintf('[OK] OR5 closed, mode=idle\n');

    delete(fig);
    fprintf('[OK] OR5 Path Planning Test PASSED\n');
catch ME
    fprintf('[ERR] %s\n', ME.message);
    for i=1:min(numel(ME.stack),6)
        fprintf('  at %s line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
    try, delete(fig); catch; end
end


%% ---- 本地算法副本（or5_path_planning.m 中为 local function，外部不可见） ----
function [pathR, pathC, totalPx] = gridBFS(roadMask, sR, sC, eR, eC)
    [H, W] = size(roadMask);
    margin = 150;
    rMin = max(1, min(sR,eR)-margin); rMax = min(H, max(sR,eR)+margin);
    cMin = max(1, min(sC,eC)-margin); cMax = min(W, max(sC,eC)+margin);
    [pathR, pathC, totalPx] = bfsInBox(roadMask, rMin, rMax, cMin, cMax, sR, sC, eR, eC);
    if isempty(pathR)
        [pathR, pathC, totalPx] = bfsInBox(roadMask, 1, H, 1, W, sR, sC, eR, eC);
    end
end

function [pathR, pathC, totalPx] = bfsInBox(roadMask, rMin, rMax, cMin, cMax, sR, sC, eR, eC)
    sub = roadMask(rMin:rMax, cMin:cMax);
    [sH, sW] = size(sub);
    lsR = sR-rMin+1; lsC = sC-cMin+1;
    leR = eR-rMin+1; leC = eC-cMin+1;
    if lsR<1||lsR>sH||lsC<1||lsC>sW||~sub(lsR,lsC)||leR<1||leR>sH||leC<1||leC>sW||~sub(leR,leC)
        pathR=[]; pathC=[]; totalPx=inf; return;
    end
    if lsR==leR && lsC==leC, pathR=sR; pathC=sC; totalPx=0; return; end
    N = sH*sW;
    prev = zeros(N,1);
    queue = zeros(N,1);
    head=1; tail=1;
    sLin = lsR + (lsC-1)*sH;
    eLin = leR + (leC-1)*sH;
    prev(sLin) = -1;
    queue(tail) = sLin; tail = tail+1;
    dr = [-1;1;0;0]; dc = [0;0;-1;1];
    found = false;
    while head < tail
        cur = queue(head); head = head+1;
        if cur == eLin, found = true; break; end
        cr = mod(cur-1, sH)+1;
        cc = floor((cur-1)/sH)+1;
        for k = 1:4
            nr = cr+dr(k); nc = cc+dc(k);
            if nr<1||nr>sH||nc<1||nc>sW, continue; end
            if ~sub(nr,nc), continue; end
            nLin = nr + (nc-1)*sH;
            if prev(nLin) ~= 0, continue; end
            prev(nLin) = cur;
            queue(tail) = nLin; tail = tail+1;
        end
    end
    if ~found, pathR=[]; pathC=[]; totalPx=inf; return; end
    pathLin = eLin; cur = eLin;
    while cur ~= sLin
        cur = prev(cur);
        pathLin = [cur; pathLin];
    end
    pathR = zeros(numel(pathLin),1);
    pathC = zeros(numel(pathLin),1);
    for i = 1:numel(pathLin)
        lr = mod(pathLin(i)-1, sH)+1;
        lc = floor((pathLin(i)-1)/sH)+1;
        pathR(i) = lr + rMin - 1;
        pathC(i) = lc + cMin - 1;
    end
    totalPx = numel(pathLin) - 1;
end

function [r, c] = findNearestRoadPixel(roadMask, col, row)
    [rr, cc] = find(roadMask);
    if isempty(rr), r=0; c=0; return; end
    d2 = (cc-col).^2 + (rr-row).^2;
    [~, i] = min(d2);
    r = rr(i); c = cc(i);
end
