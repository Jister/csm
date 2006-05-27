function res = gpm(params)
% params.laser_ref  The #first scan $\frac{pi}{4}$#
% params.laser_sens
% params.maxAngularCorrectionDeg
% params.maxLinearCorrection
% params.sigma


	params_required(params, 'laser_sens');
	params_required(params, 'laser_ref');
	params = params_set_default(params, 'maxAngularCorrectionDeg', 25);
	params = params_set_default(params, 'maxLinearCorrection',    0.4);
	params = params_set_default(params, 'maxIterations',           20);
	params = params_set_default(params, 'sigma',                 0.01);
	params = params_set_default(params, 'interactive',  false);

	%% Compute surface orientation for \verb|params.laser_ref| and \verb|params.laser_sens|
	params = compute_surface_orientation(params);

	%% Number of constraints generated (total)
	k=1;

	%% \verb| ngenerated(a)|: number of constraints generated by point $a$ in \verb|laser_ref|.
	ngenerated = zeros(1, params.laser_ref.nrays);
	
	%% \verb|ngeneratedb(b)|: number of constraints generated by $b$ in \verb|laser_sens|.
	ngeneratedb = zeros(1, params.laser_sens.nrays);
	
	%% Iterate only on points which have a valid orientation.
	for j=find(params.laser_ref.alpha_valid)

		alpha_j = params.laser_ref.alpha(j);
		p_j = params.laser_ref.points(:,j);

		%% This finds a bound for the maximum variation of $\theta$ for 
		%% a rototranslation such that 
		%%  \[|t|\leq|t|_{\text{max}}=\verb|maxLinearCorrection|\]
		%% and
		%% \[|\varphi|\leq|\varphi|_{\text{max}}=\verb|maxAngularCorrectionDeg|\]
		%%  
		%% The bound is given by 
		%% \[ |\delta| \leq |\varphi|_{\text{max}} + \text{atan}{\frac{|t|_{\text{max}}}{|p_j|}}\]
	
		delta = abs(deg2rad(params.maxAngularCorrectionDeg)) + ...
		        abs(atan(params.maxLinearCorrection/norm(p_j)));
		
		angleRes = pi / size(params.laser_sens.points,2);
		range = ceil(delta/angleRes);
		from = j-range;
		to = j+range;
		from = max(from, 1);
		to   = min(to, size(params.laser_sens.points,2));
			
		
		for i=from:to
		
			if params.laser_sens.alpha_valid(i)==0
				continue;
			end
		
			alpha_i = params.laser_sens.alpha(i);
			phi = alpha_j - alpha_i;
			phi = normAngle(phi);
			
			if abs(phi) > deg2rad(params.maxAngularCorrectionDeg)
				continue
			end
			
			p_i = params.laser_sens.points(:,i);
			%% \newcommand{\fp}{\mathbf{p}}
			%% $\hat{T} = \fp_j - R_\phi \fp_j$
			T = p_j - rot(phi) * p_i;
			
	
			if norm(T) > params.maxLinearCorrection
				continue
			end
			
			weight=1;
			weight = weight * sqrt(params.laser_ref.alpha_error(j));
			weight = weight * sqrt(params.laser_sens.alpha_error(i));
			weight=sqrt(weight);
	
					
			res.corr{k}.T = T;
			res.corr{k}.phi = phi; 
			% Surface normal
			res.corr{k}.alpha = alpha_j; 
			res.corr{k}.weight = 1/weight;
			res.corr{k}.i = i; 
			res.corr{k}.j = j; 
			
			%% Keep track of how many generated particles per point
			ngenerated(j) = ngenerated(j) + 1;
			ngeneratedb(i) = ngeneratedb(i) + 1;
			%% Keep track of how many generated particles.
			k=k+1;
		end
	end
	
	%% Number of correspondences.
	N = size(res.corr,2);
	fprintf('Number of corr.: %d\n', N);
	
	% build L matrix (Nx2) 
	L = zeros(N,2); L2 = zeros(2*N,3);
	Y = zeros(N,1); Y2 = zeros(2*N,1);
	W = zeros(N,1); W2 = zeros(2*N,1);
	Phi = zeros(N,1);
	samples = zeros(3,N);
	for k=1:N
		L(k,:) = vers(res.corr{k}.alpha)';
		Y(k,1) = vers(res.corr{k}.alpha)' * res.corr{k}.T;
		W(k,1) = res.corr{k}.weight;
		Phi(k,1) = res.corr{k}.phi;
		block = [vers(res.corr{k}.alpha)' 0; 0 0 1];
		L2((k-1)*2+1:(k-1)*2+2,1:3) = block;
		Y2((k-1)*2+1:(k-1)*2+2,1) = [Y(k,1); res.corr{k}.phi]; 
		W2((k-1)*2+1:(k-1)*2+2,1) = [res.corr{k}.weight;res.corr{k}.weight];
		
		samples(:,k) = [res.corr{k}.T; res.corr{k}.phi];
	end
	
	theta = hill_climbing(Phi, W, deg2rad(20), mean(Phi), 20, deg2rad(0.001));
	fprintf('Theta: %f\n', rad2deg(theta));
		
	X = mean(samples,2);
	X(3) = theta;
	for it=1:params.maxIterations
		fprintf(strcat(' X: ',pv(X),'\n'))
		Sigma = diag([0.5 0.5 deg2rad(40)].^2);
		
		M1 = zeros(3,3); M2 = zeros(3,1); block=zeros(3,2); by=zeros(2,1);
		% update weights
		for k=1:N
			myX = [res.corr{k}.T; res.corr{k}.phi];
			weight = W(k,1) * mynormpdf( myX-X, [0;0;0], Sigma);

			va = vers(res.corr{k}.alpha);
			block = [va' 0; 0 0 1];
			by = [va' * res.corr{k}.T; res.corr{k}.phi];
			M1 = M1 + block' * weight * block;
			M2 = M2 + block' * weight * by;
		end
		Xhat = inv(M1) * M2;
		
		delta = X-Xhat;
		X = Xhat;% X(3) = theta;
		if norm(delta(1:2)) < 0.00001
			break
		end
		
		pause(0.1)
	end

	% second alternative
	Inf3 = zeros(3,3);
	
	for k=1:N
		alpha        = res.corr{k}.alpha; %% $\alpha$
		v_alpha      = vers(alpha);
		v_dot_alpha  = vers(alpha + pi/2);
		T            =  res.corr{k}.T;
		R_phi        = rot(res.corr{k}.phi);
		R_dot_phi    = rot(res.corr{k}.phi + pi/2);
		i            = res.corr{k}.i;
		j            = res.corr{k}.j;
		v_j          = vers(params.laser_ref.theta(j));
		v_i          = vers(params.laser_sens.theta(i)); % + X(3) XXX
		cos_beta     = v_alpha' * v_i;
		p_j          = params.laser_ref.points(:,j);
		p_i          = params.laser_sens.points(:,i);
		ngi          = ngeneratedb(res.corr{k}.i);
		ngj          = ngenerated(res.corr{k}.j);
		
		sigma_alpha = deg2rad(6.4);
		sigma = params.sigma;
		noises = diag([ngi*sigma_alpha^2 ngj*sigma_alpha^2 ...
		              ngi*sigma^2 ngj*sigma^2]);

		n_alpha_i = v_alpha'*R_dot_phi*p_i;
		n_alpha_j = v_dot_alpha'*(T)+ v_alpha'*R_dot_phi*p_i;

		n_sigma_i =  v_alpha'* R_phi * v_i + cos_beta;
		n_sigma_j =  - v_alpha'*  v_j;
		
		L_k = [v_alpha' 0; 0 0 1];
		M_k = [ n_alpha_i n_alpha_j n_sigma_i n_sigma_j; 1 1 0 0 ];
		R_k =  M_k * noises * M_k';
		I_k = L_k' * inv(R_k) * L_k; 
		
		Inf3 = Inf3 + I_k;
		
	end
	
	Inf3
	Inf3(1:2,1:2)
	Cov = inv(Inf3(1:2,1:2));
	
	res.X = X;
	res.Phi = Phi;
	res.W = W;
	res.samples = samples;
	res.laser_ref=params.laser_ref;
	res.laser_sens=params.laser_sens;
	res.Inf = Inf;
	res.Cov = Cov;
	res.Cov3 = inv(Inf3);
	
	
function p = mynormpdf(x, mu, sigma);
    mahal = (x-mu)' * inv(sigma) * (x-mu);    
	 p = (1 / sqrt(2*pi * det(sigma))) * exp(-0.5*mahal); % XXX
	 
function res = hill_climbing(x, weight, sigma, x0, iterations, precision)
% hill_climbing(x, weight, sigma, x0, iterations, precision)
	for i=1:iterations
		for j=1:size(x)
			updated_weight(j) =  weight(j) * mynormpdf(x(j), x0, sigma^2);
			%updated\_weight(j) =  weight(j) * exp( -abs(x(j)- x0)/ (sigma));
		end
		
		x0new = sum(x .* updated_weight') / sum(updated_weight);
		delta = abs(x0-x0new);
		x0 = x0new;
		
		fprintf(' - %f \n', rad2deg(x0));
		
		if delta < precision
			break
		end
	end
	
	res = x0;

function res = compute_surface_orientation(params)
	%% Find a parameter of scale
	n = params.laser_ref.nrays-1;
	for i=1:n
		dists(i) = norm( params.laser_ref.points(:,i)-params.laser_ref.points(:,i+1));
	end
	dists=sort(dists);
	
	%params.scale = mean(dists(n/2:n-n/5))*2;
	params.scale = max(dists(1:n-5))*2;
	fprintf('scale: %f\n', params.scale);
	
	if not(isfield(params.laser_ref, 'alpha_valid'))
		fprintf('Computing surface normals for ld1.\n');
		params.laser_ref = computeSurfaceNormals(params.laser_ref, params.scale);
	end
	
	if not(isfield(params.laser_sens, 'alpha_valid'))
		fprintf('Computing surface normals for ld2.\n');
		params.laser_sens = computeSurfaceNormals(params.laser_sens, params.scale);
	end
	
	res = params;
	