// ============================================================================
// Reads the current image from an existing Microsoft.App/jobs resource.
// Lives in its own module so the parent template can consume the image
// string as a plain output without creating a circular dependency on the
// new job resource (same name, same deployment).
// ============================================================================

@description('Existing Container Apps Job name')
param name string

resource existingJob 'Microsoft.App/jobs@2024-03-01' existing = {
  name: name
}

output image string = existingJob.properties.template.containers[0].image
