package io.github.kjhilger.agenticorchestration;

import io.camunda.client.annotation.Deployment;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.support.SpringBootServletInitializer;

@SpringBootApplication
@Deployment(resources = {
        "classpath:natural-hazard-information.bpmn",
        "classpath:enter-city.form",
        "classpath:read-hazard-information.form"
})
public class ProcessApplication extends SpringBootServletInitializer {

    public static void main(String[] args) {
        SpringApplication.run(ProcessApplication.class, args);
    }
}
