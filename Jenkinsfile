pipeline {
    // La VM-TOOLS funciona como agente único en esta entrega académica.
    // Solo permitir ramas de colaboradores de confianza en Jenkins.
    agent any

    options {
        skipDefaultCheckout()
        disableConcurrentBuilds()
    }

    environment {
        RELEASE_VERSION = '1.0.0'
        GHCR_OWNER = 'ovfabri'
    }

    stages {
        stage('Checkout') {
            steps {
                // Obtiene el commit exacto que se analizará y empaquetará.
                deleteDir()
                checkout scm
                sh 'git log -1 --format=%H'
            }
        }

        stage('Pruebas y cobertura') {
            steps {
                // Fija Bun y exige LCOV para publicar cobertura a SonarQube.
                sh '''
                    test "$(bun --version)" = "1.4.3"
                    bun test
                    test -s coverage/lcov.info
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'coverage/lcov.info', allowEmptyArchive: true
                }
            }
        }

        stage('SonarQube') {
            when {
                anyOf {
                    branch 'main'
                    branch 'demo/quality-gate'
                }
            }
            steps {
                script {
                    // Community Build analiza main y la rama de demo por separado.
                    env.SONAR_PROJECT_KEY = env.BRANCH_NAME == 'main' ? 'medisur' : 'medisur-demo'
                    def scannerHome = tool 'SonarScanner'
                    withSonarQubeEnv('SonarQube') {
                        // Community Build analiza la rama principal de cada proyecto.
                        withEnv(["SCANNER_HOME=${scannerHome}", "BRANCH_NAME="]) {
                            sh '''
                                "$SCANNER_HOME/bin/sonar-scanner" -Dsonar.projectKey="$SONAR_PROJECT_KEY"
                            '''
                        }
                    }
                }
            }
        }

        stage('Quality Gate') {
            when {
                anyOf {
                    branch 'main'
                    branch 'demo/quality-gate'
                }
            }
            steps {
                // Un gate rojo cancela el flujo antes de construir/publicar.
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true, webhookSecretId: 'sonar-webhook'
                }
            }
        }

        stage('Construir imagen') {
            when { branch 'main' }
            steps {
                // La etiqueta contiene versión y SHA del commit, sin latest.
                script {
                    env.IMAGE_REF = sh(
                        script: 'bash scripts/build-image.sh "$RELEASE_VERSION"',
                        returnStdout: true
                    ).trim()
                }
            }
        }

        stage('Publicar en GHCR') {
            when { branch 'main' }
            steps {
                // La credencial vive solo durante login y se pasa por stdin.
                withCredentials([usernamePassword(
                    credentialsId: 'ghcr-publisher',
                    usernameVariable: 'GHCR_USER',
                    passwordVariable: 'GHCR_TOKEN'
                )]) {
                    sh '''
                        set +x
                        DOCKER_CONFIG="$(mktemp -d)"
                        export DOCKER_CONFIG
                        trap 'rm -rf -- "$DOCKER_CONFIG"' EXIT
                        printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
                        docker push "$IMAGE_REF"
                    '''
                }
                echo "Imagen publicada: ${env.IMAGE_REF}"
            }
        }

        stage('Desplegar y verificar en Kubernetes') {
            when { branch 'main' }
            steps {
                // Usa kubeconfig acotado; rollout o smoke fallido intenta rollback.
                withCredentials([file(credentialsId: 'k8s-kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        set -eu
                        namespace=medisur
                        deployment=medisur-api

                        kubectl apply -k kubernetes
                        kubectl -n "$namespace" set image "deployment/$deployment" "api=$IMAGE_REF"
                        if ! kubectl -n "$namespace" rollout status "deployment/$deployment" --timeout=180s; then
                            echo 'El rollout no quedó listo; se intenta volver a la revisión anterior.' >&2
                            kubectl -n "$namespace" rollout undo "deployment/$deployment"
                            kubectl -n "$namespace" rollout status "deployment/$deployment" --timeout=180s || true
                            exit 1
                        fi

                        node_ip=$(kubectl get nodes -o 'jsonpath={.items[0].status.addresses[?(@.type=="InternalIP")].address}')
                        if ! bun scripts/smoke-test.js "http://$node_ip" "$GIT_COMMIT" "$RELEASE_VERSION"; then
                            echo 'Falló la prueba de humo; se intenta volver a la revisión anterior.' >&2
                            kubectl -n "$namespace" rollout undo "deployment/$deployment"
                            kubectl -n "$namespace" rollout status "deployment/$deployment" --timeout=180s || true
                            exit 1
                        fi
                    '''
                }
            }
        }
    }
}
