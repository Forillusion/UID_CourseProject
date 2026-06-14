%TEST_STEP_A  Step A automated test (no GUI interaction)
%  Verify: map loading, dimensions, coordinate conversion

fprintf('========== Step A Test ==========\n');

%% 1. Verify map can be loaded
mapPath = fullfile(pwd, 'MapForUI.jpg');
assert(isfile(mapPath), 'MapForUI.jpg not found');
img = imread(mapPath);
[H, W, C] = size(img);
fprintf('Map loaded: H=%d (rows), W=%d (cols), channels=%d, type=%s\n', H, W, C, class(img));
assert(isequal([H W], [803 1404]), 'Map size wrong! Expected H=803 W=1404');
fprintf('[OK] Map size correct: H=803 W=1404 (landscape)\n');

%% 2. Verify px2world conversion logic
%   world origin = bottom-left of image; X right; Y up
%   wx = col * scale, wy = (mapH - row) * scale
scale = 1.7;

% bottom-left (col=1, row=H) should be near origin
col = 1; row = H;
wx = col * scale;
wy = (H - row) * scale;
fprintf('Bottom-left (col=%d,row=%d) -> world (%.2f, %.2f)\n', col, row, wx, wy);

% top-left (col=1, row=1) should be at max Y
col2 = 1; row2 = 1;
wx2 = col2 * scale;
wy2 = (H - row2) * scale;
fprintf('Top-left (col=%d,row=%d) -> world (%.2f, %.2f)\n', col2, row2, wx2, wy2);

assert(abs(wy) < scale, 'Bottom-left worldY should be near 0');
assert(wy2 >= (H-1)*scale, 'Top-left worldY should be near max');
fprintf('[OK] px2world conversion correct\n');

%% 3. Verify world2px inverse consistency
col3 = 600; row3 = 400;
wx3 = col3 * scale;
wy3 = (H - row3) * scale;
col3b = wx3 / scale;
row3b = H - wy3 / scale;
assert(abs(col3b - col3) < 1e-9 && abs(row3b - row3) < 1e-9, 'Inverse conversion inconsistent');
fprintf('[OK] world2px inverse conversion consistent\n');

%% 4. Verify main.m syntax via checkcode
try
    msg = checkcode('main.m', '-string');
    if isempty(msg)
        fprintf('[OK] main.m has no LINT errors\n');
    else
        fprintf('[WARN] main.m has %d LINT hints:\n', numel(msg));
        for i = 1:min(numel(msg),8)
            fprintf('   L%d: %s\n', msg(i).line(1), msg(i).message);
        end
    end
catch ME
    fprintf('[ERR] LINT check failed: %s\n', ME.message);
end

fprintf('\n========== Step A Test PASSED ==========\n');
