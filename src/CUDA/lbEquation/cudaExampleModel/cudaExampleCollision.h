#ifndef CUDAEXAMPLECOLLISION_H
#define CUDAEXAMPLECOLLISION_H

/**
 * @file cudaExampleCollision.h
 * @author Ezequiel O. Fogliatto
 * @date 14 Feb 2020
 * @brief Operaci\'on de modelo de colisi\'on simplificado
 */


/**
 * Operaci\'on de modelo de colisi\'on simplificado
 * @param field Arreglo unidimensional de la funcion de distribucion
 * @param sum Arreglo unidimensional resultante
 * @param mesh Malla
 */

#include <dataTypes.h>

#include <cudaLatticeMesh.h>


extern "C" __global__ void cudaExampleCollision(cudaBasicMesh* mesh, cuscalar* field, cuscalar* rho, cuscalar* U );


#endif // CUDAEXAMPLECOLLISION_H
