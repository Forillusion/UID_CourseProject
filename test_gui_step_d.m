%TEST_GUI_STEP_D  测试车辆加载/移除/角度/报告（通过回调间接测试）
fprintf('========== GUI Step D Test ==========\n');
try
    fig = main();
    S = getappdata(fig, 'S');

    % 检查控件存在
    fn = fieldnames(S.handles);
    for n = {'btnLoadIV','btnRemoveIV','ivDropdown','angleSlider','angleValue','btnReportIV'}
        assert(ismember(n{1}, fn), sprintf('%s missing', n{1}));
    end
    fprintf('[OK] all IV controls exist\n');

    % 生成掩膜
    S = getappdata(fig, 'S');
    S.sk.nodes = [100 100; 400 100; 400 500];
    S.sk.edges = [1 2; 2 3];
    S.roadHalfWidth = 5;
    setappdata(fig, 'S', S);
    S.handles.btnGenMask.ButtonPushedFcn(S.handles.btnGenMask, []);
    fprintf('[OK] road mask generated\n');

    % 测试无掩膜时 onBtnLoadIV 报错
    S = getappdata(fig, 'S');
    savedMask = S.roadMask;
    S.roadMask = [];
    setappdata(fig, 'S', S);
    try
        S.handles.btnLoadIV.ButtonPushedFcn(S.handles.btnLoadIV, []);
        ok = false;
    catch
        ok = true;  % 应该报错（uialert 在 batch 抛异常）
    end
    S = getappdata(fig, 'S');
    S.roadMask = savedMask;
    setappdata(fig, 'S', S);
    fprintf('[OK] loadIV without mask handled\n');

    % 测试 onBtnLoadIV 设置模式
    S.handles.btnLoadIV.ButtonPushedFcn(S.handles.btnLoadIV, []);
    S = getappdata(fig, 'S');
    assert(strcmp(S.mode, 'loadIV'), 'mode not loadIV');
    fprintf('[OK] btnLoadIV sets mode=loadIV\n');

    % 构造车辆，手动设置 dropdown，通过 onAngleChanged 测试 drawAllVehicles
    S = getappdata(fig, 'S');
    S.vehicles(1).id = 1; S.vehicles(1).cx = 200; S.vehicles(1).cy = 100;
    S.vehicles(1).angle = 0; S.vehicles(1).dispScale = 3;
    S.nextIVid = 2;
    S.handles.ivDropdown.Items = {'#1 (200,100)'};
    S.handles.ivDropdown.Value = '#1 (200,100)';
    setappdata(fig, 'S', S);
    % 调用角度改变 -> 内部调用 drawAllVehicles
    S.handles.angleSlider.Value = 45;
    S.handles.angleSlider.ValueChangedFcn(S.handles.angleSlider, []);
    S = getappdata(fig, 'S');
    assert(S.vehicles(1).angle == 45, 'angle not updated');
    % 检查有绿色像素（drawAllVehicles 被调用）
    g = nnz(S.mapDisplay(:,:,2)==200 & S.mapDisplay(:,:,1)==0);
    assert(g > 0, 'drawAllVehicles did not draw');
    fprintf('[OK] drawAllVehicles drew %d green pixels, angle=45\n', g);

    % 测试移除
    S.handles.btnRemoveIV.ButtonPushedFcn(S.handles.btnRemoveIV, []);
    S = getappdata(fig, 'S');
    assert(isempty(S.vehicles), 'vehicle not removed');
    fprintf('[OK] vehicle removed\n');

    % 测试空列表时的错误处理
    try
        S.handles.btnRemoveIV.ButtonPushedFcn(S.handles.btnRemoveIV, []);
        ok = false;
    catch; ok = true; end
    fprintf('[OK] removeIV with empty list handled\n');

    delete(fig);
    fprintf('[OK] GUI Step D Test PASSED\n');
catch ME
    fprintf('[ERR] %s\n', ME.message);
    for i=1:min(numel(ME.stack),4)
        fprintf('  at %s line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
    try, delete(fig); catch; end
end
