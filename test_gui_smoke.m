%TEST_GUI_SMOKE  GUI 冒烟测试
fprintf('========== GUI Smoke Test ==========\n');

try
    fig = main();
    fprintf('[OK] main() executed\n');
    assert(isvalid(fig), 'figure invalid');

    S = getappdata(fig, 'S');

    % 检查 mapOrigin (注意 size 对 3D 矩阵取两值时第二值=各维乘积)
    assert(~isempty(S.mapOrigin), 'Map not loaded');
    [H,W,C] = size(S.mapOrigin);
    assert(isequal([H W C],[803 1404 3]), sprintf('Map size wrong: %dx%dx%d', H,W,C));
    fprintf('[OK] Map loaded: %dx%d\n', H, W);

    % 检查 handles
    fn = fieldnames(S.handles);
    assert(ismember('statusBar', fn), 'no statusBar');
    assert(ismember('coordX', fn), 'no coordX');
    assert(ismember('coordY', fn), 'no coordY');
    assert(ismember('rotEdit', fn), 'no rotEdit');
    fprintf('[OK] handles OK: %s\n', strjoin(fn, ', '));

    % 检查 statusBar 文本已设置
    sb = S.handles.statusBar;
    assert(isvalid(sb), 'statusBar invalid');
    assert(~isempty(sb.Text), 'statusBar text empty');
    fprintf('[OK] statusBar text set (len=%d)\n', strlength(sb.Text));

    % 检查 axes
    assert(isvalid(S.ax), 'ax invalid');
    fprintf('[OK] axes valid\n');

    delete(fig);
    fprintf('[OK] Figure closed cleanly\n');
catch ME
    fprintf('[ERR] %s\n', ME.message);
    for i=1:min(numel(ME.stack),4)
        fprintf('  at %s line %d\n', ME.stack(i).name, ME.stack(i).line);
    end
    try, delete(fig); catch; end
end
fprintf('========== Done ==========\n');
