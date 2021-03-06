#include <exampleVelocity.h>

#include <stdio.h>

void exampleVelocity(scalar* rho, scalar* U, scalar* field, basicMesh* mesh) {


    // Suma de todas las componentes
    
    for( uint i = 0 ; i < mesh->nPoints ; i++ ) {


	// Velocidad local
	
	scalar lv[3] = {0,0,0};


	// Move over velocity components
	
	for( uint j = 0 ; j < 3 ; j++ ) {

	    // Move over model velocities
	    for(uint k = 0 ; k < mesh->Q ; k++) {

		lv[j] += (scalar)mesh->lattice.vel[k*3+j] * field[i*mesh->Q+k];
		    
	    }
	    
	}


	// Add interaction force and divide by density
	for( uint j = 0 ; j < 3 ; j++ ) {

	    lv[j] = lv[j] / rho[i];
	
	}


	// Copy to global array
	for(uint j = 0 ; j < 3 ; j++) {
	
	    U[i*3+j] = lv[j];
	
	}



    }
    

}
