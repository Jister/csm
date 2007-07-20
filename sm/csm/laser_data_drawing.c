#include "laser_data_drawing.h"

const char*ld_reference_name[4] = { "invalid","odometry","estimate","true_pose"};

const char*ld_reference_to_string(ld_reference r) {
	return ld_reference_name[r];
}


int ld_get_bounding_box(LDP ld, double bb_min[2], double bb_max[2],
	double pose[3], double horizon) {

	int rays_used = 0;
	int i; for(i=0;i<ld->nrays;i++) {
		if(!ld->valid[i]) continue;
		if(ld->readings[i]>horizon) continue;

		double p0[2] = {
			cos(ld->theta[i]) * ld->readings[i],
			sin(ld->theta[i]) * ld->readings[i]
		};
		
		double p[2];
		transform_d(p0,pose,p);
		
		if(0 == rays_used) {
			bb_min[0] = bb_max[0] = p[0];
			bb_min[1] = bb_max[1] = p[1];
		} else {
			int j=0; for(j=0;j<2;j++) {
				bb_min[j] = GSL_MIN(bb_min[j], p[j]);
				bb_max[j] = GSL_MAX(bb_max[j], p[j]);
			}
		}

		rays_used++;
	}
		
	return rays_used > 3;
}
	
void lda_get_bounding_box(LDP *lda, int nld, double bb_min[2], double bb_max[2],
	double offset[3], ld_reference use_reference, double horizon) {
	
	int k;
	for(k=0;k<nld;k++) {
		LDP ld = lda[k];

		double *ref = ld_get_reference_pose(ld, use_reference);
		if(!ref) {
			sm_error("Pose %s not set in scan #%d.\n", 
				ld_reference_to_string(use_reference), k);
			continue;
		}
		
		double pose[3];
		oplus_d(offset, ref, pose);
	
		if(k==0) 
			ld_get_bounding_box(ld, bb_min, bb_max, pose, horizon);
		else {
			double this_min[2], this_max[2];
			ld_get_bounding_box(ld, this_min, this_max, pose, horizon);
			int i; for(i=0;i<2;i++) {
				bb_min[i] = GSL_MIN(bb_min[i], this_min[i]);
				bb_max[i] = GSL_MAX(bb_max[i], this_max[i]);
			}
		}
	}
}

double * ld_get_reference_pose(LDP ld, ld_reference use_reference) {
	double * pose;
	switch(use_reference) {
		case Odometry: pose = ld->odometry; break;
		case Estimate: pose = ld->estimate; break;
		case True_pose: pose = ld->true_pose; break;
		default: exit(-1);
	}
	if(any_nan(pose, 3)) {
		sm_error("Required field '%s' not set in laser scan.\n", 
			ld_reference_to_string(use_reference) );
		return 0;
	}
	return pose;
}
