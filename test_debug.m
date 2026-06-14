%TEST_DEBUG  诊断 UI 控件创建和属性设置
fprintf('========== Debug Test ==========\n');

fig = uifigure('Position', [100 100 800 600]);
pnl = uipanel(fig, 'Units','pixels', 'Position', [0 0 320 600], 'BorderType','none');
gl = uigridlayout(pnl, [5 1]);
gl.RowHeight = repmat({'fit'},5,1);
gl.ColumnWidth = {'1x'};

% 测试1: 直接创建 uilabel
try
    lbl = uilabel(gl, 'Text','hello');
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    fprintf('[1] uilabel created. class=%s\n', class(lbl));
    fprintf('    Text=%s\n', lbl.Text);
catch ME
    fprintf('[1] FAILED: %s\n', ME.message);
end

% 测试2: 用 set 设置 Text
try
    set(lbl, 'Text', 'world');
    fprintf('[2] set Text via set() OK: %s\n', lbl.Text);
catch ME
    fprintf('[2] set() FAILED: %s\n', ME.message);
end

% 测试3: 用点号设置 Text
try
    lbl.Text = 'dot';
    fprintf('[3] dot-set Text OK: %s\n', lbl.Text);
catch ME
    fprintf('[3] dot-set FAILED: %s\n', ME.message);
end

% 测试4: isgraphics 检查
fprintf('[4] isgraphics(lbl)=%d, isvalid(lbl)=%d\n', isgraphics(lbl), isvalid(lbl));

% 测试5: feval('uilabel', ...)
try
    lbl2 = feval('uilabel', gl, 'Text','feval-test');
    lbl2.Layout.Row = 2; lbl2.Layout.Column = 1;
    fprintf('[5] feval uilabel OK: Text=%s\n', lbl2.Text);
catch ME
    fprintf('[5] feval FAILED: %s\n', ME.message);
end

delete(fig);
fprintf('========== Debug Done ==========\n');
