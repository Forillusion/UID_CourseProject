%TEST_STEP_B  Step B test: skeleton data ops + geometry algorithms
fprintf('========== Step B Test ==========\n');

%% 1. Test ptToSegDist
% point on segment midpoint
A = [0 0]; B = [10 0]; P = [5 0];
d = ptToSegDist(P, A, B);
assert(abs(d) < 1e-9, 'ptToSegDist failed: on-segment');
fprintf('[OK] ptToSegDist on-segment: d=%.6f\n', d);

% point perpendicular
P = [5 3];
d = ptToSegDist(P, A, B);
assert(abs(d - 3) < 1e-9, 'ptToSegDist failed: perpendicular');
fprintf('[OK] ptToSegDist perpendicular: d=%.6f (expect 3)\n', d);

% point beyond endpoint
P = [15 0];
d = ptToSegDist(P, A, B);
assert(abs(d - 5) < 1e-9, 'ptToSegDist failed: beyond endpoint');
fprintf('[OK] ptToSegDist beyond-endpoint: d=%.6f (expect 5)\n', d);

% point beyond start
P = [-3 4];
d = ptToSegDist(P, A, B);
assert(abs(d - 5) < 1e-9, 'ptToSegDist failed: beyond start');
fprintf('[OK] ptToSegDist beyond-start: d=%.6f (expect 5)\n', d);

%% 2. Test bresenham
% horizontal line
pts = bresenham(0, 0, 5, 0);
assert(size(pts,1) == 6, 'bresenham horizontal count wrong');
fprintf('[OK] bresenham horizontal: %d points\n', size(pts,1));

% vertical line
pts = bresenham(0, 0, 0, 5);
assert(size(pts,1) == 6, 'bresenham vertical count wrong');
fprintf('[OK] bresenham vertical: %d points\n', size(pts,1));

% diagonal
pts = bresenham(0, 0, 4, 4);
assert(size(pts,1) == 5, 'bresenham diagonal count wrong');
fprintf('[OK] bresenham diagonal: %d points\n', size(pts,1));

%% 3. Test skeleton data manipulation (simulate sketch + erase)
sk_nodes = zeros(0,2);
sk_edges = zeros(0,2,'int32');
sketchChain = [];

% Add 4 nodes in a chain: (1,1)->(2,2)->(3,3)->(4,4)
clicks = [1 1; 2 2; 3 3; 4 4];
for i = 1:size(clicks,1)
    sk_nodes(end+1,:) = clicks(i,:);
    nodeIdx = size(sk_nodes,1);
    if ~isempty(sketchChain)
        sk_edges(end+1,:) = [sketchChain(end), nodeIdx];
    end
    sketchChain(end+1) = nodeIdx;
end
assert(size(sk_nodes,1)==4, 'nodes count wrong');
assert(size(sk_edges,1)==3, 'edges count wrong');
fprintf('[OK] sketch: %d nodes, %d edges\n', size(sk_nodes,1), size(sk_edges,1));

% Simulate erase edge 2 (between node 2 and 3)
eraseIdx = 2;
sk_edges(eraseIdx,:) = [];
% cleanup: node 2 and 3 are now only connected to each other? no.
% After removing edge2: edges are [1,2] and [3,4]. Node 2 connected to 1, node 3 to 4.
% All nodes still used, so no cleanup.
used = false(size(sk_nodes,1),1);
used(sk_edges(:)) = true;
fprintf('[OK] after erase edge2: edges=%d, used=%s\n', size(sk_edges,1), mat2str(used));

% Now erase all edges, all nodes become isolated
sk_edges = zeros(0,2,'int32');
used = false(size(sk_nodes,1),1);
used(sk_edges(:)) = true;
assert(~any(used), 'all nodes should be unused');
fprintf('[OK] after erase all: %d nodes, all isolated\n', size(sk_nodes,1));

%% 4. Test cleanupNodes logic
S = struct();
S.sk.nodes = [1 1; 2 2; 3 3; 4 4; 5 5];
S.sk.edges = [1 2; 4 5];  % nodes 3 is isolated
% Run cleanup
used = false(size(S.sk.nodes,1),1);
used(S.sk.edges(:)) = true;
keepIdx = find(used);
newMap = zeros(size(S.sk.nodes,1),1);
newMap(keepIdx) = 1:numel(keepIdx);
S.sk.edges(:,1) = newMap(S.sk.edges(:,1));
S.sk.edges(:,2) = newMap(S.sk.edges(:,2));
S.sk.nodes = S.sk.nodes(keepIdx,:);
assert(size(S.sk.nodes,1)==4, 'cleanup should keep 4 nodes');
assert(isequal(S.sk.edges, [1 2; 3 4]), 'edge remapping wrong');
fprintf('[OK] cleanupNodes: %d nodes, edges=%s\n', size(S.sk.nodes,1), mat2str(S.sk.edges'));

%% 5. LINT check
msg = checkcode('main.m', '-id');
fprintf('main.m LINT hints: %d\n', numel(msg));

fprintf('\n========== Step B Test PASSED ==========\n');


%% ===== Local functions (copies from main.m for testing) =====
function d = ptToSegDist(P, A, B)
    AB = B - A;
    AP = P - A;
    ab2 = dot(AB, AB);
    if ab2 == 0
        d = norm(P - A);
        return;
    end
    t = dot(AP, AB) / ab2;
    t = max(0, min(1, t));
    closest = A + t * AB;
    d = norm(P - closest);
end

function pts = bresenham(x0, y0, x1, y1)
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
