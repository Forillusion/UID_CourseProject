%TEST_OR1_POPUP  测试OR1弹窗工作流
fprintf('========== OR1 Popup Test ==========\n');
try
    fig = main();
    S = getappdata(fig, 'S');

    %% 1. 打开OR1弹窗
    or1_skeleton('open', fig);
    S = getappdata(fig, 'S');
    assert(isvalid(S.or1Fig), 'OR1 window not created');
    assert(isfield(S, 'or1'), 'S.or1 not set');
    fprintf('[OK] OR1 popup opened\n');

    %% 2. 点击提取骨架按钮
    S.or1.btnSketch.ButtonPushedFcn(S.or1.btnSketch, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.sketchState, 'sketching'), 'not sketching');
    assert(strcmp(S.mode, 'sketch'), 'mode not sketch');
    fprintf('[OK] sketch mode activated\n');

    %% 3. 模拟点击主窗口画骨架
    or1_skeleton('click', fig, 100, 100, 'normal');
    or1_skeleton('click', fig, 300, 100, 'normal');
    or1_skeleton('click', fig, 300, 400, 'normal');
    S = getappdata(fig, 'S');
    assert(size(S.sk.nodes, 1) == 3, sprintf('nodes=%d', size(S.sk.nodes,1)));
    assert(size(S.sk.edges, 1) == 2, sprintf('edges=%d', size(S.sk.edges,1)));
    fprintf('[OK] drew 3 nodes, 2 edges\n');
    % Check red skeleton visible
    redPx = nnz(S.mapDisplay(:,:,1)==255 & S.mapDisplay(:,:,2)==0 & S.mapDisplay(:,:,3)==0);
    assert(redPx > 0, 'red skeleton not visible');
    fprintf('[OK] red skeleton visible: %d px\n', redPx);

    %% 4. 点击提取结束
    S.or1.btnFinish.ButtonPushedFcn(S.or1.btnFinish, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.sketchState, 'finalized'), 'not finalized');
    assert(~isempty(S.roadMask), 'no roadMask');
    % Blue road should be visible now, red hidden
    bluePx = nnz(S.mapDisplay(:,:,3)>150 & S.mapDisplay(:,:,1)<100);
    assert(bluePx > 0, 'blue road not shown');
    fprintf('[OK] finalized: mask=%d px, blue=%d px\n', sum(S.roadMask(:)), bluePx);

    %% 5. 再次提取骨架（隐藏蓝路，显示红线）
    S.or1.btnSketch.ButtonPushedFcn(S.or1.btnSketch, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.sketchState, 'sketching'), 'not sketching again');
    redPx2 = nnz(S.mapDisplay(:,:,1)==255 & S.mapDisplay(:,:,2)==0 & S.mapDisplay(:,:,3)==0);
    assert(redPx2 > 0, 'red not shown in re-sketching');
    fprintf('[OK] re-sketching shows red: %d px\n', redPx2);

    %% 6. 擦除模式
    S.or1.btnErase.ButtonPushedFcn(S.or1.btnErase, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.sketchState, 'erasing'), 'not erasing');
    assert(strcmp(get(fig,'Pointer'),'circle'), 'cursor not circle');
    assert(strcmp(S.or1.btnErase.Text, '返回点选'), 'erase button text wrong');
    fprintf('[OK] erase mode + circle cursor\n');

    %% 7. 擦除一条线段 (click on midpoint of edge 1->2)
    or1_skeleton('click', fig, 200, 100, 'normal');  % midpoint of (100,100)-(300,100)
    S = getappdata(fig, 'S');
    assert(size(S.sk.edges, 1) == 1, sprintf('after erase edges=%d', size(S.sk.edges,1)));
    fprintf('[OK] erased 1 edge, remaining: %d\n', size(S.sk.edges,1));

    %% 8. 关闭弹窗（自动完成）
    or1_skeleton('close', fig);
    S = getappdata(fig, 'S');
    assert(isempty(S.or1Fig) || ~isvalid(S.or1Fig), 'OR1 window still open');
    assert(strcmp(S.sketchState, 'finalized'), 'should auto-finalize on close');
    assert(strcmp(S.mode, 'idle'), 'mode should be idle after close');
    fprintf('[OK] closed + auto-finalized\n');

    %% 9. 清空道路（通过重新打开弹窗）
    or1_skeleton('open', fig);
    S = getappdata(fig, 'S');
    S.or1.btnClear.ButtonPushedFcn(S.or1.btnClear, []);
    S = getappdata(fig, 'S');
    assert(isempty(S.sk.edges), 'edges not cleared');
    assert(isempty(S.roadMask), 'mask not cleared');
    assert(strcmp(S.sketchState, 'idle'), 'not idle after clear');
    fprintf('[OK] cleared to idle\n');

    %% 10. 关闭
    close(S.or1Fig);

    delete(fig);
    fprintf('[OK] OR1 Popup Test PASSED\n');
catch ME
    fprintf('[ERR] %s\n', ME.message);
    for i=1:min(numel(ME.stack),4)
        fprintf('  at %s line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
    try, delete(fig); catch; end
end
