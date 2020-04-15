/*

  Maxwell construction

  Construccion de Maxwell isotermica

 */


extern "C" {
    
#include <latticeMesh.h>

#include <basic.h>

#include <momentoFunciondist.h>   

#include <momentoVelocity.h>

#include <fuerza.h>

#include <energy.h>

#include <IO.h>

#include "writeDebug.h"

}

#include <stdio.h>

#include <cuda_runtime.h>

#include <cudaTest.h>

#include <cudaLatticeMesh.h>

#include <cudaExampleModel.h>

#include <cudaMomentoFunciondist.h>

#include <cudaEnergy.h>

#include <cudaFuerza.h>

#include <math.h>





int main(int argc, char** argv) {


    
    
    printf( "                    \n" );
    printf( "     o-----o-----o  \n" );
    printf( "     | -   |   - |  \n" );
    printf( "     |   - | -   |                          cudaVdWColumnHT \n" );
    printf( "     o<----o---->o  \n" );
    printf( "     |   - | -   |  Estratificación de fluido Van der Waals con temperatura no uniforme\n" );
    printf( "     | -   |   - |  \n" );
    printf( "     o-----o-----o  \n\n" );


    // Argumentos:
    //
    // - argv[1] = Pasos de tiempo
    // - argv[2] = Intervalo de escritura
    // - argv[3] = xgrid

    
    int xgrid = atoi( argv[3] );


    // Pasos de tiempo
    
    uint timeSteps = atoi( argv[1] );

    uint wrtInterval = atoi( argv[2] );

    uint nwrite = (uint)(timeSteps/wrtInterval + 1);

    uint* timeList = (uint*)malloc( nwrite * sizeof(uint) );
    
    for(int i = 0; i < nwrite; i++)
        timeList[i] = i*wrtInterval;
            
    cuscalar delta_t = 1.0;
    


    // Informacion sobre el device

    cudaDeviceProp prop;

    {
	int count;
	
	cudaGetDeviceCount( &count );
	
	for (int i=0; i< count; i++)
	    cudaGetDeviceProperties( &prop, i );

	printf( "\n -- Informacion general del device --  \n\n" );
	printf( "  Nombre: %s\n", prop.name );
	printf( "  Compute capability: %d.%d\n", prop.major, prop.minor );
	printf( "  Total global mem: %.2f GB\n", (float)prop.totalGlobalMem / 1000000000 );
	printf( "  Total constant Mem: %ld\n", prop.totalConstMem );
	printf( "\n\n" );

    }



    // Inicializacion de tiempo

    timeInfo Time;

    startTime(&Time);


    

    // Parametros del modelo

    cuscalar G = -1.0;

    cuscalar c = 1.0;

    cuscalar sigma = 0.125;
    

    
    // Constantes de EOS

    cuscalar a = 0.5;

    cuscalar b = 4;

    
    
    // Gravedad

    scalar g[3] = {0,-1.234567e-07,0};

    

    // Lectura de malla

    basicMesh mesh = readBasicMesh();

    cudaBasicMesh cmesh;

    hostToDeviceMesh( &cmesh, &mesh );
    






    // Alocacion de funcion de distribucion como arreglo unidimensional
    //
    // Si se desea acceder a los componentes de field usando dos indices,
    // entonces puede hacerse algo como
    //
    // for( i = 0 ; i < mesh.nPoints ; i++)
    //     for( j = 0 ; j < mesh.Q ; j++)
    //         idx = i*mesh.Q + j;

    uint fsize = mesh.nPoints * mesh.Q;
    
    cuscalar* field_f = (cuscalar*)malloc( fsize * sizeof(cuscalar) );

    cuscalar* field_g = (cuscalar*)malloc( fsize * sizeof(cuscalar) );    
    

    
    // Alocacion de arreglo de salida

    cuscalar* rho = (cuscalar*)malloc( mesh.nPoints * sizeof(cuscalar) ); //Density

    cuscalar* U = (cuscalar*)malloc( 3 * mesh.nPoints * sizeof(cuscalar) ); // Velocity macroscopic

    cuscalar* Temp = (cuscalar*)malloc( mesh.nPoints * sizeof(cuscalar) ); // Temperature

    cuscalar* fint = (cuscalar*)malloc( mesh.nPoints * 3 * sizeof(cuscalar) ); // Interaction force

    cuscalar* f = (cuscalar*)malloc( mesh.nPoints * 3 * sizeof(cuscalar) ); // Total force ( volumetric add interaction )

    cuscalar* heat = (cuscalar*)malloc( mesh.nPoints * sizeof(cuscalar) ); // Heat source
    

       

    // Inicializacion de densidad

    for( uint i = 0 ; i < mesh.nPoints ; i++ ) {

    	rho[i] = (1.0 / 12.0) + (rand() % (3)-1)*0.01*1.0/12.0;

    	/* if( mesh.points[i][1] < 3 ) { */

    	/*     rho[i] = 0.09; */

    	/* } */

    	/* else { */

    	/*     rho[i] = 0.07; */

    	/* } */


    }
   



    // Inicializacion de velocidad
    
    for( uint i = 0 ; i < mesh.nPoints ; i++ ){
	
    	for( uint j = 0 ; j < 3 ; j++ ) {
	    
    	    U[i*3+j] = 0;

    	}

    }


    // Inicializacion de Temperatura

    for( uint i = 0 ; i < mesh.nPoints ; i++ )
    	Temp[i] = 0.036667;
 



    // Factores de relajacion para colision

    momentoModelCoeffs relax;

    relax.Tau[0] = 1.0;
    relax.Tau[1] = 0.8;
    relax.Tau[2] = 1.1;
    relax.Tau[3] = 1.0;
    relax.Tau[4] = 1.1;
    relax.Tau[5] = 1.0;
    relax.Tau[6] = 1.1;
    relax.Tau[7] = 0.8;
    relax.Tau[8] = 0.8;


    // Factores de relajacion para energia

    energyCoeffs energyRelax;
    
    energyRelax.Tau[0] = 1.0;
    energyRelax.Tau[1] = 1.0;
    energyRelax.Tau[2] = 1.0;
    energyRelax.Tau[3] = 0.8;
    energyRelax.Tau[4] = 1.0;
    energyRelax.Tau[5] = 0.8;
    energyRelax.Tau[6] = 1.0;
    energyRelax.Tau[7] = 1.0;
    energyRelax.Tau[8] = 1.0;

    energyRelax.alpha_1 = 1;
    energyRelax.alpha_2 = 1;
    energyRelax.Cv = 1;    




    // Inicializacion de campos en el host

    fuerzaFuerzaint(fint, rho, Temp , &mesh, G, c, mesh.lattice.cs2, a, b);

    fuerzaFuerzatotal(f, fint, rho, g, &mesh);

    energyS( &mesh, heat, rho, Temp, U, &energyRelax, mesh.lattice.cs2, delta_t, b);
    
    momentoFeq( &mesh, field_f, rho, U);

    energyEqDistMomento( &mesh, field_g, Temp, U, &energyRelax );
    
    




    
    
    // Alocacion de memoria en el device y copia

    cuscalar* deviceField_f;

    cudaMalloc( (void**)&deviceField_f, fsize*sizeof(cuscalar) );

    cudaMemcpy( deviceField_f, field_f, fsize*sizeof(cuscalar), cudaMemcpyHostToDevice );    



    cuscalar* deviceField_g;

    cudaMalloc( (void**)&deviceField_g, fsize*sizeof(cuscalar) );

    cudaMemcpy( deviceField_g, field_g, fsize*sizeof(cuscalar), cudaMemcpyHostToDevice );    



    cuscalar* deviceSwap;

    cudaMalloc( (void**)&deviceSwap, fsize*sizeof(cuscalar) );    

    

    cuscalar* deviceRho;

    cudaMalloc( (void**)&deviceRho, mesh.nPoints*sizeof(cuscalar) );

    cudaMemcpy( deviceRho, rho, mesh.nPoints*sizeof(cuscalar), cudaMemcpyHostToDevice );


    
    cuscalar* deviceU;

    cudaMalloc( (void**)&deviceU, 3*mesh.nPoints*sizeof(cuscalar) );

    cudaMemcpy( deviceU, U, 3*mesh.nPoints*sizeof(cuscalar), cudaMemcpyHostToDevice );


    
    cuscalar* deviceT;

    cudaMalloc( (void**)&deviceT, mesh.nPoints*sizeof(cuscalar) );

    cudaMemcpy( deviceT, Temp, mesh.nPoints*sizeof(cuscalar), cudaMemcpyHostToDevice );


    
    cuscalar* deviceFint;

    cudaMalloc( (void**)&deviceFint, 3*mesh.nPoints*sizeof(cuscalar) );

    cudaMemcpy( deviceFint, fint, 3*mesh.nPoints*sizeof(cuscalar), cudaMemcpyHostToDevice );



    cuscalar* deviceF;

    cudaMalloc( (void**)&deviceF, 3*mesh.nPoints*sizeof(cuscalar) );

    cudaMemcpy( deviceF, f, 3*mesh.nPoints*sizeof(cuscalar), cudaMemcpyHostToDevice );

    

    cuscalar* deviceGravity;

    cudaMalloc( (void**)&deviceGravity, 3*sizeof(cuscalar) );

    cudaMemcpy( deviceGravity, g, 3*sizeof(cuscalar), cudaMemcpyHostToDevice );    


    
    cuscalar* deviceTau;

    cudaMalloc( (void**)&deviceTau, 9*sizeof(cuscalar) );

    cudaMemcpy( deviceTau, relax.Tau, 9*sizeof(cuscalar), cudaMemcpyHostToDevice );


    
    cuscalar* deviceEnergyTau;

    cudaMalloc( (void**)&deviceEnergyTau, 9*sizeof(cuscalar) );

    cudaMemcpy( deviceEnergyTau, energyRelax.Tau, 9*sizeof(cuscalar), cudaMemcpyHostToDevice );


    cuscalar* deviceHeat;

    cudaMalloc( (void**)&deviceHeat, mesh.nPoints*sizeof(cuscalar) );

    cudaMemcpy( deviceHeat, heat, mesh.nPoints*sizeof(cuscalar), cudaMemcpyHostToDevice );    







    
    

    // Antes de comenzar la simulacion, escritura de los campos iniciales

    char scfields[2][100] = {"rho", "T"};

    char vfields[1][100] = {"U"};

    updateCaseFile(scfields, 2, vfields, 1, timeList, nwrite);
    

    writeMeshToEnsight( &mesh );

    writeScalarToEnsight(scfields[0], rho, &mesh, 0);

    writeScalarToEnsight(scfields[1], Temp, &mesh, 0);

    writeVectorToEnsight(vfields[0], U, &mesh, 0);

    
    

    // Ejecucion LB

    for( uint ts = 1 ; ts < (timeSteps+1) ; ts++ ) {


	// Ecuacion de energia

    	cudaEnergyCollision<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>( deviceField_g, deviceU, deviceT, deviceHeat, deviceEnergyTau, energyRelax.alpha_1, energyRelax.alpha_2,
								   cmesh.Q, cmesh.nPoints, cmesh.lattice.M, cmesh.lattice.invM ); cudaDeviceSynchronize();


	cudaStreaming<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>( deviceField_g, deviceSwap, cmesh.nb, cmesh.nPoints, cmesh.Q ); cudaDeviceSynchronize();

	
	uint bd;

	boundaryIndex(&mesh, "Y1", &bd);

	cudaFixedTBoundary<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>( deviceField_g, deviceT, deviceU, cmesh.bd.bdPoints, cmesh.nb, cmesh.lattice.invM,
								  energyRelax.alpha_1, energyRelax.alpha_2, 0.036667, bd, cmesh.bd.nbd,
								  cmesh.bd.maxCount, cmesh.Q );   cudaDeviceSynchronize();
	
	boundaryIndex(&mesh, "Y0", &bd);

	cudaFixedTBoundary<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>( deviceField_g, deviceT, deviceU, cmesh.bd.bdPoints, cmesh.nb, cmesh.lattice.invM,
								  energyRelax.alpha_1, energyRelax.alpha_2, 0.033333, bd, cmesh.bd.nbd,
								  cmesh.bd.maxCount, cmesh.Q );   cudaDeviceSynchronize();


	cudaEnergySource<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>( deviceHeat, deviceRho, deviceT, deviceU, deviceEnergyTau, energyRelax.alpha_1, energyRelax.alpha_2,
								mesh.lattice.cs2, energyRelax.Cv, b, cmesh.nPoints, cmesh.Q, cmesh.lattice.vel, cmesh.nb );
	cudaDeviceSynchronize();


	cudaEnergyTemp<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>( deviceT, deviceField_g, deviceHeat, cmesh.nPoints, cmesh.Q);  cudaDeviceSynchronize();
	

	

	
	// Ecuaciones hidrodinamicas

    	cudaMomentoCollision<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>( deviceField_f, deviceRho, deviceU, deviceF, deviceFint, deviceT,
    								    deviceTau, cmesh.lattice.M, cmesh.lattice.invM, cmesh.nPoints,
    								    cmesh.Q, delta_t, a, b, c, mesh.lattice.cs2, G, sigma); cudaDeviceSynchronize();


	cudaStreaming<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>( deviceField_f, deviceSwap, cmesh.nb, cmesh.nPoints, cmesh.Q ); cudaDeviceSynchronize();

	
    	cudaMomentoDensity<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>( deviceField_f, deviceRho, cmesh.nPoints, cmesh.Q);  cudaDeviceSynchronize();


    	cudaFuerzaFuerzaint<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>( deviceFint, deviceRho, deviceT, cmesh.nPoints, cmesh.Q, cmesh.lattice.vel,
								   cmesh.lattice.reverse, cmesh.nb, G, c, mesh.lattice.cs2, a, b);  cudaDeviceSynchronize();

    	cudaFuerzaFuerzatotal<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>( deviceF, deviceFint, deviceRho, deviceGravity, cmesh.nPoints);  cudaDeviceSynchronize();


    	cudaMomentoVelocity<<<ceil(mesh.nPoints/xgrid)+1,xgrid>>>(deviceField_f, deviceRho, deviceU, deviceF,
								  cmesh.lattice.vel, mesh.nPoints, mesh.Q);  cudaDeviceSynchronize();

	
	


    	// Escritura de campos
	
    	for( uint wt = 0 ; wt < nwrite ; wt++ ) {

    	    if( timeList[wt] == ts ) {


    		// Copia de vuelta al host

    		cudaMemcpy( field_f, deviceField_f, fsize*sizeof(cuscalar), cudaMemcpyDeviceToHost );

    		cudaMemcpy( field_g, deviceField_g, fsize*sizeof(cuscalar), cudaMemcpyDeviceToHost );		
		
    		cudaMemcpy( rho, deviceRho, mesh.nPoints*sizeof(cuscalar), cudaMemcpyDeviceToHost );

    		cudaMemcpy( Temp, deviceT, mesh.nPoints*sizeof(cuscalar), cudaMemcpyDeviceToHost );

    		cudaMemcpy( U, deviceU, 3*mesh.nPoints*sizeof(cuscalar), cudaMemcpyDeviceToHost );
		

		
    	    	scalar elap = elapsedTime(&Time);

    	    	printf( " Tiempo = %d\n", ts );
		
    	    	printf( " Tiempo de ejecución = %.4f segundos\n\n", elap );
		

    	    	writeScalarToEnsight(scfields[0], rho, &mesh, wt);

    	    	writeScalarToEnsight(scfields[1], Temp, &mesh, wt);

    	    	writeVectorToEnsight(vfields[0], U, &mesh, wt);


		
		/* writeDebug(field_f, field_g, rho, Temp, U, heat, mesh.nPoints, mesh.Q); */

		

    	    }

    	}

	
	
    }
    

   

    
    // Limpieza de memoria host

    freeBasicMesh( &mesh );

    free( field_f );

    free( field_g );    

    free( rho );

    free( U );

    free( Temp );

    free( f );

    free( fint );

    
    // Limpieza de memoria device

    cudaFree( deviceField_f );

    cudaFree( deviceField_g );    

    cudaFree( deviceRho );

    cudaFree( deviceU );

    cudaFree( deviceT );

    cudaFree( deviceFint );

    cudaFree( deviceF );

    cudaFree( deviceTau);

    cudaFree( deviceEnergyTau);

    cudaFree( deviceGravity);


    
    scalar elap = elapsedTime(&Time);
	
    printf( "\n Fin. Tiempo total = %.4f segundos\n\n", elap );
    
   
    return 0;

}
