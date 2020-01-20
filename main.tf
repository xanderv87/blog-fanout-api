provider "aws" {
  profile = "blue-playground"
  region = "${var.region}"
}

### SNS Topic ###

resource "aws_sns_topic" "fanout_sns" {
  name = "fanout-topic"
}

### IAM policy ###

resource "aws_iam_role" "apigateway_sns" {
  name = "fanout-apigateway-sns-role"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "apigateway.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
    ]
}
EOF
}
resource "aws_iam_role_policy" "apigateway_sns_policy" {
  name = "test_policy"
  role = "${aws_iam_role.apigateway_sns.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "${aws_sns_topic.fanout_sns.arn}"
    }
  ]
}
EOF
}

### Api Endpoint ###

resource "aws_api_gateway_rest_api" "api" {
  name = "demo-api-fanout"
}
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration_response.integration_response]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name = "demo"
}

resource "aws_api_gateway_resource" "resource" {
  depends_on = [
    aws_api_gateway_rest_api.api]
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id = aws_api_gateway_rest_api.api.root_resource_id
  path_part = "fanout"
}

resource "aws_api_gateway_method_response" "response-200" {
  depends_on = [
    aws_api_gateway_resource.resource,
    aws_api_gateway_method.method]
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  status_code = "200"
}

resource "aws_api_gateway_method" "method" {
  depends_on = [
    aws_api_gateway_resource.resource]
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "NONE"
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "integration" {
  depends_on = [
    aws_api_gateway_resource.resource,
    aws_api_gateway_method.method]
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type = "AWS"
  uri = "arn:aws:apigateway:${var.region}:sns:path//"
  credentials = aws_iam_role.apigateway_sns.arn
  request_parameters = {
    "integration.request.querystring.Action" = "'Publish'"
    "integration.request.querystring.TopicArn" = "'${aws_sns_topic.fanout_sns.arn}'"
    "integration.request.querystring.Message" = "method.request.body"
  }
  request_templates = {
    "application/json" = ""
  }
}
resource "aws_api_gateway_integration_response" "integration_response" {
  depends_on = [
    aws_api_gateway_resource.resource,
    aws_api_gateway_method.method,
    aws_api_gateway_integration.integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  status_code = "200"
  selection_pattern = ""

  response_templates = {
    "application/json" = <<EOF
      {"body": "Message received."}
    EOF
  }
}

resource "aws_sqs_queue" "fanout_queue" {
  name = "fanout-queue"
}

resource "aws_sns_topic_subscription" "enervalis_fanout_input_sqs" {
  topic_arn = aws_sns_topic.fanout_sns.arn
  protocol = "sqs"
  endpoint = aws_sqs_queue.fanout_queue.arn
}