#------------------ Lattice Box 2D------------------#

# latticeBox2D

add_executable(latticeBox2D "latticeBox2D.c" "genericBoundary.c" "periodicX.c" "periodicY.c" "periodicXY.c")

target_link_libraries(latticeBox2D ${PROJECT_LINK_LIBS} ${PROJECT_LINK_LIBS})
