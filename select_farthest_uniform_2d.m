function idx = select_farthest_uniform_2d(Mx, My, m)
    % SELECT_FARTHEST_UNIFORM_2D  Greedy farthest-point selection on a 2D grid.
    %
    % 选 m 个点尽量 uniform 分散在 Mx × My 阵列上, 用 farthest-point greedy 算法:
    %   - 第 1 个点: 最接近阵列中心的点
    %   - 第 k 个点: 距离已选点集最近距离最大的候选点 (max-min distance)
    %
    % 这种算法给出 well-distributed 点云 (相比 select_uniform_points_2d 的
    % linspace+round 算法, 避免 N=5/17 等奇数时的 grid quirk: 仅选 4 角 +
    % 边缘 / 跳过整列)
    %
    % Inputs:
    %   Mx, My - 阵列 x/y 维度 (e.g., 6, 4)
    %   m      - 选点数
    %
    % Output:
    %   idx    - m × 1 vector of linear indices (1-based, column-major)

    if m >= Mx * My
        idx = (1:Mx*My).';
        return;
    end

    [IX, IY] = ndgrid(1:Mx, 1:My);
    pts = [IX(:), IY(:)];   % (Mx*My, 2)
    n = size(pts, 1);

    % 第 1 个点: 最接近中心
    cx = (Mx + 1) / 2; cy = (My + 1) / 2;
    d_center = (pts(:,1) - cx).^2 + (pts(:,2) - cy).^2;
    [~, i1] = min(d_center);
    selected = i1;

    % Greedy farthest-point: 每次选距离已选点集最近距离最大的候选点
    d_min = inf(n, 1);
    for k = 2:m
        % 更新所有候选点到最新加入点的距离
        last = pts(selected(end), :);
        d_to_last = (pts(:,1) - last(1)).^2 + (pts(:,2) - last(2)).^2;
        d_min = min(d_min, d_to_last);

        d_min(selected) = -1;   % 排除已选
        [~, i_next] = max(d_min);
        selected = [selected; i_next]; %#ok<AGROW>
    end

    idx = sub2ind([Mx, My], pts(selected, 1), pts(selected, 2));
end
