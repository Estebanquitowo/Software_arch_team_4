require "test_helper"
require "yaml"

class KubernetesScalingTest < ActiveSupport::TestCase
  def manifest(path)
    YAML.safe_load_file(Rails.root.join("k8s", path))
  end

  test "one Service selects all three identical Rails replicas" do
    deployment = manifest("base/web-deployment.yaml")
    service = manifest("base/web-service.yaml")
    labels = deployment.dig("spec", "template", "metadata", "labels")
    assert_equal 3, deployment.dig("spec", "replicas")
    assert_equal deployment.dig("spec", "selector", "matchLabels"), service.dig("spec", "selector")
    service.dig("spec", "selector").each { |key, value| assert_equal value, labels.fetch(key) }
    assert_equal 3000, service.dig("spec", "ports", 0, "targetPort")
    assert_includes [ nil, "None" ], service.dig("spec", "sessionAffinity")
    %w[cache search full].each do |overlay|
      assert_nil manifest("overlays/#{overlay}/web-patch.yaml").dig("spec", "replicas")
    end
  end

  test "all replicas mount the configured image root from one persistent claim" do
    pod = manifest("base/web-deployment.yaml").dig("spec", "template", "spec")
    root = manifest("base/configmap.yaml").dig("data", "IMAGE_STORAGE_PATH")
    mount = pod.fetch("containers").first.fetch("volumeMounts").find { |item| item["mountPath"] == root }
    assert mount
    volume = pod.fetch("volumes").find { |item| item["name"] == mount["name"] }
    pvc = manifest("base/images-pvc.yaml")
    assert_equal pvc.dig("metadata", "name"), volume.dig("persistentVolumeClaim", "claimName")
    assert_equal [ "ReadWriteOnce" ], pvc.dig("spec", "accessModes")
    assert_includes manifest("base/kustomization.yaml").fetch("resources"), "images-pvc.yaml"
  end

  test "Rails uses CookieStore and every replica references the shared configuration and secret" do
    assert_equal ActionDispatch::Session::CookieStore, Rails.application.config.session_store
    sources = manifest("base/web-deployment.yaml").dig("spec", "template", "spec", "containers", 0, "envFrom")
    assert_includes sources, { "configMapRef" => { "name" => "app-config" } }
    assert_includes sources, { "secretRef" => { "name" => "app-secret" } }
    assert manifest("base/secret.yaml").fetch("stringData").key?("SECRET_KEY_BASE")
  end

  test "edge proxy targets the stable web Service rather than individual Rails Pods" do
    deployment = manifest("overlays/edge/haproxy-deployment.yaml")
    service = manifest("overlays/edge/haproxy-service.yaml")
    container = deployment.dig("spec", "template", "spec", "containers", 0)

    assert_equal "web:80", container.fetch("env").find { |item| item["name"] == "RAILS_BACKEND" }.fetch("value")
    assert_equal({ "app" => "haproxy" }, service.dig("spec", "selector"))
    assert_equal [ 80, 443 ], service.dig("spec", "ports").map { |item| item["port"] }
    assert_includes manifest("overlays/edge/kustomization.yaml").fetch("resources"), "../full"
  end
end
