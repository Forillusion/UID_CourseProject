%TEST_STEP_F  Step F test: distance measurement algorithms
fprintf('========== Step F Test ==========\n');

scale = 1.7;

%% 1. Test computeTrackLength - single segment
pts = [100 100; 200 100];
len = computeTrackLength(pts, scale);
expected = 100 * scale;  % 100 pixels * 1.7
assert(abs(len - expected) < 1e-9, sprintf('single seg: %.4f != %.4f', len, expected));
fprintf('[OK] single segment: %.2f m (expect %.2f)\n', len, expected);

%% 2. Test computeTrackLength - multiple segments (L-shape)
pts2 = [100 100; 200 100; 200 200];
len2 = computeTrackLength(pts2, scale);
expected2 = (100 + 100) * scale;
assert(abs(len2 - expected2) < 1e-9, 'L-shape length wrong');
fprintf('[OK] L-shape: %.2f m (expect %.2f)\n', len2, expected2);

%% 3. Test computeTrackLength - diagonal
pts3 = [0 0; 3 4];
len3 = computeTrackLength(pts3, scale);
expected3 = 5 * scale;   % 3-4-5 triangle
assert(abs(len3 - expected3) < 1e-9, 'diagonal length wrong');
fprintf('[OK] diagonal: %.2f m (expect %.2f)\n', len3, expected3);

%% 4. Test computeTrackLength - empty or single point
len4 = computeTrackLength(zeros(0,2), scale);
assert(len4 == 0, 'empty track should be 0');
len5 = computeTrackLength([100 100], scale);
assert(len5 == 0, 'single point should be 0');
fprintf('[OK] empty/single: 0\n');

%% 5. Test two-point distance (Euclidean)
p1 = [100 100]; p2 = [130 140];
d = norm(p2 - p1) * scale;
expected_d = sqrt(30^2 + 40^2) * scale;  % 50 * 1.7
assert(abs(d - expected_d) < 1e-9, 'two-point distance wrong');
fprintf('[OK] two-point: %.2f m (expect %.2f)\n', d, expected_d);

%% 6. Test multi-segment track
pts6 = [0 0; 10 0; 10 10; 20 10; 20 20];
len6 = computeTrackLength(pts6, scale);
expected6 = (10+10+10+10) * scale;
assert(abs(len6 - expected6) < 1e-9, 'multi-seg wrong');
fprintf('[OK] multi-segment: %.2f m\n', len6);

fprintf('\n========== Step F Test PASSED ==========\n');

%% ===== Local function =====
function len = computeTrackLength(pts, scale)
    len = 0;
    for i = 2:size(pts,1)
        len = len + norm(pts(i,:) - pts(i-1,:)) * scale;
    end
end
